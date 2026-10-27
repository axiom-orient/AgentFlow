#if canImport(Darwin)
  import Observation
#endif

/// One main-actor state owner. Only `send` applies the pure reducer.
///
/// Cancellation revokes delivery from a command generation. It does not undo external effects.
/// A dependency that commits a durable effect must preserve its receipt outside this store.
@MainActor
#if canImport(Darwin)
  @Observable
#endif
public final class Store<
  State: Sendable, Action: Sendable, Operation: Sendable, Values: Dependencies
> {
  public private(set) var state: State

  // Only UI observation is platform-specific. Runtime logic executes on every host.
  private let reducer: Reducer<State, Action, Operation>
  private let runner: CommandRunner<Operation, Action, Values>

  // A private reference kept in a `let` is not tracked by @Observable. This also avoids
  // conditional @ObservationIgnored attributes, which conflict with macro expansion.
  // It is bookkeeping owned only by this Store, not a second product-state owner.
  @MainActor
  private final class Runtime {
    // Membership is the sole result-delivery authority. Keys only select active work.
    var tasks: [UInt64: Task<Void, Never>] = [:]
    var keyedTasks: [CancellationID: UInt64] = [:]
    var nextToken: UInt64 = 0
    var pendingActions: [Action] = []
    var isReducing = false
  }
  private let runtime = Runtime()

  public init(
    initialState: State, reducer: Reducer<State, Action, Operation>,
    runner: CommandRunner<Operation, Action, Values>
  ) {
    state = initialState
    self.reducer = reducer
    self.runner = runner
  }

  isolated deinit {
    for task in runtime.tasks.values { task.cancel() }
  }

  /// Synchronously drains actions in FIFO order, then returns.
  /// Reentrant sends (including Observation callbacks) queue behind the current transition.
  public func send(_ action: Action) {
    runtime.pendingActions.append(action)
    guard !runtime.isReducing else { return }
    runtime.isReducing = true
    defer {
      runtime.pendingActions.removeAll(keepingCapacity: true)
      runtime.isReducing = false
    }
    var index = 0
    while index < runtime.pendingActions.count {
      let next = runtime.pendingActions[index]
      index += 1
      let commands = reducer.reduce(into: &state, action: next)
      for command in commands { interpret(command) }
    }
  }

  /// Revokes delivery before requesting cooperative cancellation.
  public func cancelAll() {
    let live = Array(runtime.tasks.values)
    runtime.tasks.removeAll(keepingCapacity: true)
    runtime.keyedTasks.removeAll(keepingCapacity: true)
    for task in live { task.cancel() }
  }

  /// Runtime introspection, not observable presentation state.
  public func isRunning(_ id: CancellationID) -> Bool { runtime.keyedTasks[id] != nil }

  /// Awaits still-owned work, including commands issued by its result actions.
  /// Work revoked before selection is not joined. Revoking a selected task does not
  /// interrupt an existing await of that task. Cancel infinite streams before calling.
  /// This is a deterministic test/integration boundary, not an automatic UI lifecycle hook.
  public func finish() async {
    while let task = runtime.tasks.values.first { await task.value }
  }

  private func interpret(_ command: Command<Operation>) {
    switch command {
    case .cancel(let id): cancel(id)
    case .run(let operation, let policy):
      switch policy {
      case .concurrent: start(operation, id: nil)
      case .cancelInFlight(let id):
        cancel(id)
        start(operation, id: id)
      case .dropIfRunning(let id):
        guard runtime.keyedTasks[id] == nil else { return }
        start(operation, id: id)
      }
    }
  }

  private func start(_ operation: Operation, id: CancellationID?) {
    // Never recycle a live or historical delivery token.
    precondition(runtime.nextToken < UInt64.max, "AgentFlow command identity exhausted")
    runtime.nextToken += 1
    let token = runtime.nextToken
    if let id { runtime.keyedTasks[id] = token }
    let runner = self.runner
    let send = Send<Action> { [weak self] action in
      await self?.receive(action, token: token)
    }
    // MainActor serializes registration before this task can start.
    runtime.tasks[token] = Task { [weak self] in
      if !Task.isCancelled { await runner.run(operation, send: send) }
      self?.complete(token: token, id: id)
    }
  }

  private func receive(_ action: Action, token: UInt64) {
    guard runtime.tasks[token] != nil else { return }
    send(action)
  }

  private func cancel(_ id: CancellationID) {
    guard let token = runtime.keyedTasks.removeValue(forKey: id) else { return }
    runtime.tasks.removeValue(forKey: token)?.cancel()
  }

  private func complete(token: UInt64, id: CancellationID?) {
    runtime.tasks.removeValue(forKey: token)
    if let id, runtime.keyedTasks[id] == token { runtime.keyedTasks.removeValue(forKey: id) }
  }
}
