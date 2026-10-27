import AgentFlow
import Foundation
import Testing

#if canImport(Darwin)
  import Observation
#endif

private enum Event: Sendable {
  case start(Int, CommandPolicy)
  case cancel(CancellationID)
  case value(Int)
  case startThenCancel(Int)
}
private struct Values: Dependencies { let probe: Probe }

/// Continuation handshakes, not sleeps or scheduler polling, control every interleaving.
private actor Probe {
  var started: Set<Int> = []
  var completed: [Int: Bool] = [:]
  var sends: [Int: Send<Event>] = [:]
  var startWaiters: [Int: CheckedContinuation<Void, Never>] = [:]
  var finishWaiters: [Int: CheckedContinuation<Void, Never>] = [:]
  var releases: [Int: CheckedContinuation<Void, Never>] = [:]

  func run(_ id: Int, send: Send<Event>) async {
    sends[id] = send
    started.insert(id)
    startWaiters.removeValue(forKey: id)?.resume()
    // Deliberately ignore cancellation to test late-result rejection.
    await withCheckedContinuation { releases[id] = $0 }
    completed[id] = Task.isCancelled
    finishWaiters.removeValue(forKey: id)?.resume()
  }
  func waitStarted(_ id: Int) async {
    if started.contains(id) { return }
    await withCheckedContinuation { startWaiters[id] = $0 }
  }
  func waitCompleted(_ id: Int) async {
    if completed[id] != nil { return }
    await withCheckedContinuation { finishWaiters[id] = $0 }
  }
  func emit(_ id: Int, _ value: Int) async { await sends[id]?(.value(value)) }
  func release(_ id: Int) { releases.removeValue(forKey: id)?.resume() }
}

@MainActor
private func makeStore(_ probe: Probe) -> Store<[Int], Event, Int, Values> {
  Store(
    initialState: [],
    reducer: Reducer { state, action in
      switch action {
      case .start(let id, let policy): return [.run(id, policy: policy)]
      case .cancel(let id): return [.cancel(id)]
      case .value(let value):
        state.append(value)
        return []
      case .startThenCancel(let id):
        return [.run(id, policy: .cancelInFlight("job")), .cancel("job")]
      }
    },
    runner: CommandRunner(dependencies: Values(probe: probe)) { id, values, send in
      await values.probe.run(id, send: send)
    })
}

@Suite(.timeLimit(.minutes(1)))
struct StoreTests {
  @Test @MainActor func synchronousTransition() {
    let store = makeStore(Probe())
    store.send(.value(3))
    store.send(.value(7))
    #expect(store.state == [3, 7])
  }

  @Test @MainActor func replacedGenerationCannotPublish() async {
    let probe = Probe()
    let store = makeStore(probe)
    store.send(.start(1, .cancelInFlight("job")))
    await probe.waitStarted(1)
    store.send(.start(2, .cancelInFlight("job")))
    await probe.waitStarted(2)
    await probe.emit(1, 100)
    await probe.emit(2, 200)
    #expect(store.state == [200])
    #expect(store.isRunning("job"))
    await probe.release(1)
    await probe.release(2)
    await store.finish()
    await probe.waitCompleted(1)
    #expect(await probe.completed[1] == true)
    #expect(!store.isRunning("job"))
    // Escaped result channels cannot outlive completion either.
    await probe.emit(2, 300)
    #expect(store.state == [200])
  }

  @Test(arguments: [CommandPolicy.concurrent, .cancelInFlight("job"), .dropIfRunning("job")])
  @MainActor func completedSendCannotPublishIntoLaterWork(_ policy: CommandPolicy) async {
    let probe = Probe()
    let store = makeStore(probe)
    store.send(.start(1, policy))
    await probe.waitStarted(1)
    await probe.emit(1, 1)
    await probe.release(1)
    // Unlike Probe.waitCompleted, finish also joins the Store's completion cleanup.
    await store.finish()
    await probe.emit(1, 100)
    #expect(store.state == [1])

    store.send(.start(2, policy))
    await probe.waitStarted(2)
    await probe.emit(1, 200)
    await probe.emit(2, 2)
    #expect(store.state == [1, 2])
    await probe.release(2)
    await store.finish()
  }

  @Test @MainActor func cancelAllAllowsNewWorkWithoutRestoringOldSend() async {
    let probe = Probe()
    let store = makeStore(probe)
    store.send(.start(1, .cancelInFlight("job")))
    await probe.waitStarted(1)
    store.cancelAll()
    // Removed work is deliberately still suspended. finish must not join it.
    await store.finish()
    store.send(.start(2, .dropIfRunning("job")))
    await probe.waitStarted(2)
    await probe.emit(1, 100)
    await probe.emit(2, 2)
    #expect(store.state == [2])
    #expect(store.isRunning("job"))
    await probe.release(1)
    await probe.release(2)
    await store.finish()
    await probe.waitCompleted(1)
    #expect(await probe.completed[1] == true)
  }

  @Test @MainActor func cancellationRevokesBeforeTheRunnerCooperates() async {
    let probe = Probe()
    let store = makeStore(probe)
    store.send(.start(1, .cancelInFlight("job")))
    await probe.waitStarted(1)
    store.send(.cancel("job"))
    #expect(!store.isRunning("job"))
    await probe.emit(1, 999)
    #expect(store.state.isEmpty)
    await probe.release(1)
    await probe.waitCompleted(1)
    #expect(await probe.completed[1] == true)
  }

  @Test @MainActor func dropWhileRunningAndReuseAfterCompletion() async {
    let probe = Probe()
    let store = makeStore(probe)
    store.send(.start(1, .dropIfRunning("job")))
    await probe.waitStarted(1)
    store.send(.start(2, .dropIfRunning("job")))
    await probe.release(1)
    await store.finish()
    #expect(await probe.started == [1])
    store.send(.start(2, .dropIfRunning("job")))
    await probe.waitStarted(2)
    await probe.release(2)
    await store.finish()
    #expect(await probe.started == [1, 2])
  }

  @Test @MainActor func concurrentWorkHasNoImplicitOrdering() async {
    let probe = Probe()
    let store = makeStore(probe)
    store.send(.start(1, .concurrent))
    store.send(.start(2, .concurrent))
    await probe.waitStarted(1)
    await probe.waitStarted(2)
    await probe.emit(2, 2)
    await probe.emit(1, 1)
    #expect(store.state == [2, 1])
    await probe.release(1)
    await probe.release(2)
    await store.finish()
  }

  @Test @MainActor func cancelAllRevokesKeyedAndUnkeyedWork() async {
    let probe = Probe()
    let store = makeStore(probe)
    store.send(.start(1, .concurrent))
    store.send(.start(2, .cancelInFlight("job")))
    await probe.waitStarted(1)
    await probe.waitStarted(2)
    store.cancelAll()
    await probe.emit(1, 1)
    await probe.emit(2, 2)
    #expect(store.state.isEmpty)
    #expect(!store.isRunning("job"))
    await probe.release(1)
    await probe.release(2)
    await probe.waitCompleted(1)
    await probe.waitCompleted(2)
    #expect(await probe.completed[1] == true)
    #expect(await probe.completed[2] == true)
  }

  @Test @MainActor func cancellationBeforeStartDoesNotInvokeDependency() async {
    let probe = Probe()
    let store = makeStore(probe)
    store.send(.startThenCancel(1))
    // MainActor registration/cancellation finished before its Task is allowed to enter.
    await store.finish()
    #expect(await probe.started.isEmpty)
  }

  @Test @MainActor func teardownDoesNotRetainStoreAndCancelsWork() async {
    let probe = Probe()
    var store: Store<[Int], Event, Int, Values>? = makeStore(probe)
    weak let reference = store
    store?.send(.start(1, .concurrent))
    await probe.waitStarted(1)
    store = nil
    #expect(reference == nil)
    await probe.release(1)
    await probe.waitCompleted(1)
    #expect(await probe.completed[1] == true)
  }

  @Test @MainActor func cancellingOneKeyDoesNotCancelAnother() async {
    let probe = Probe()
    let store = makeStore(probe)
    store.send(.start(1, .cancelInFlight("one")))
    store.send(.start(2, .cancelInFlight("two")))
    await probe.waitStarted(1)
    await probe.waitStarted(2)
    store.send(.cancel("one"))
    await probe.emit(2, 2)
    #expect(store.state == [2])
    #expect(store.isRunning("two"))
    await probe.release(1)
    await probe.release(2)
    await store.finish()
  }

  @Test @MainActor func finishAlsoDrainsCommandsIssuedByResultActions() async {
    let store = Store(
      initialState: [Int](),
      reducer: Reducer<[Int], Int, Int> { state, value in
        state.append(value)
        return value < 20 ? [.run(value + 1)] : []
      },
      runner: CommandRunner<Int, Int, NoDependencies>(dependencies: .init()) { value, _, send in
        await send(value)
      })
    store.send(0)
    await store.finish()
    #expect(store.state == Array(0...20))
  }

  #if canImport(Darwin)
    @Test @MainActor func observationCanQueueAReentrantAction() {
      let store = makeStore(Probe())
      withObservationTracking {
        _ = store.state
      } onChange: {
        MainActor.assumeIsolated { store.send(.value(2)) }
      }
      store.send(.value(1))
      #expect(store.state == [1, 2])
    }
  #endif
}

@Test func cancellationIDRejectsEmptyDecodedInput() throws {
  #expect(throws: DecodingError.self) {
    try JSONDecoder().decode(CancellationID.self, from: Data("\"\"".utf8))
  }
  let id: CancellationID = "search"
  let encoded = try JSONEncoder().encode(id)
  #expect(try JSONDecoder().decode(CancellationID.self, from: encoded) == id)
}
