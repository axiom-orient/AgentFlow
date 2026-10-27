/// A deterministic state transition.
///
/// A reducer may mutate only the state passed to it and may describe outside work by
/// returning typed commands. It must not perform I/O, create tasks, read clocks/randomness,
/// or mutate external state.
public struct Reducer<State: Sendable, Action: Sendable, Operation: Sendable>: Sendable {
  public typealias Body = @Sendable (inout State, Action) -> [Command<Operation>]

  private let body: Body

  public init(_ body: @escaping Body) {
    self.body = body
  }

  public func reduce(into state: inout State, action: Action) -> [Command<Operation>] {
    body(&state, action)
  }
}
