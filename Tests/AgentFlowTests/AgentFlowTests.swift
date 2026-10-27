import AgentFlow
import Testing

private enum UploadState: Sendable, Equatable {
  case idle
  case uploading(progress: Int)
  case completed
}

private enum UploadAction: Sendable {
  case start
  case progress(Int)
  case finished
  case cancel
}

private enum UploadOperation: Sendable, Equatable, Codable {
  case upload
}

private let uploadID: CancellationID = "upload"

private let uploadReducer = Reducer<UploadState, UploadAction, UploadOperation> { state, action in
  switch (state, action) {
  case (.idle, .start):
    state = .uploading(progress: 0)
    return [.run(.upload, policy: .cancelInFlight(uploadID))]

  case (.uploading, let .progress(value)):
    state = .uploading(progress: value)
    return []

  case (.uploading, .finished):
    state = .completed
    return []

  case (.uploading, .cancel):
    state = .idle
    return [.cancel(uploadID)]

  default:
    return []
  }
}

private struct UploadDependencies: Dependencies, Sendable, Equatable {
  var endpoint: String
}

@Test
func reducerMutatesOnlyStateAndReturnsTypedCommands() {
  var state = UploadState.idle
  let commands = uploadReducer.reduce(into: &state, action: .start)

  #expect(state == .uploading(progress: 0))
  #expect(commands == [.run(.upload, policy: .cancelInFlight("upload"))])
}

@Test
func reducerIsDeterministic() {
  var lhs = UploadState.idle
  var rhs = UploadState.idle

  let left = uploadReducer.reduce(into: &lhs, action: .start)
  let right = uploadReducer.reduce(into: &rhs, action: .start)

  #expect(lhs == rhs)
  #expect(left == right)
}

@Test
func cancellationIsProductData() {
  var state = UploadState.uploading(progress: 5)
  let commands = uploadReducer.reduce(into: &state, action: .cancel)

  #expect(state == .idle)
  #expect(commands == [.cancel("upload")])
}

@Test
func commandRunnerUsesExplicitDependencies() async {
  actor Recorder {
    var endpoints: [String] = []
    func append(_ endpoint: String) { endpoints.append(endpoint) }
  }
  let recorder = Recorder()
  let runner = CommandRunner<UploadOperation, UploadAction, UploadDependencies>(
    dependencies: .init(endpoint: "/upload")
  ) { operation, dependencies, _ in
    switch operation {
    case .upload:
      await recorder.append(dependencies.endpoint)
    }
  }

  await runner.run(.upload, send: Send { _ in })
  #expect(await recorder.endpoints == ["/upload"])
}
