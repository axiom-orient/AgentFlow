/// Sends command results back through the action loop.
public struct Send<Action: Sendable>: Sendable {
  private let body: @Sendable (Action) async -> Void

  public init(_ body: @escaping @Sendable (Action) async -> Void) {
    self.body = body
  }

  public func callAsFunction(_ action: Action) async {
    await body(action)
  }
}

/// Interprets typed command operations using explicit dependencies.
///
/// The body is intentionally nonthrowing. Expected failures must become actions. Cancellation
/// should terminate work without fabricating success.
public struct CommandRunner<Operation: Sendable, Action: Sendable, Values: Dependencies>: Sendable {
  public typealias Body = @Sendable (Operation, Values, Send<Action>) async -> Void

  public let dependencies: Values
  private let body: Body

  public init(dependencies: Values, _ body: @escaping Body) {
    self.dependencies = dependencies
    self.body = body
  }

  @concurrent
  public func run(_ operation: Operation, send: Send<Action>) async {
    guard !Task.isCancelled else { return }
    await body(operation, dependencies, send)
  }
}
