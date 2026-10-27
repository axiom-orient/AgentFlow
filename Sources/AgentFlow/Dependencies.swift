/// Marker protocol for a feature's explicit live/test dependencies.
///
/// AgentFlow intentionally has no global dependency registry, property wrapper, task-local
/// lookup, or service locator. Define one plain `Sendable` struct per command runner and
/// conform it to this protocol.
public protocol Dependencies: Sendable {}

/// Use when a command runner has no external dependencies.
public struct NoDependencies: Dependencies, Sendable, Equatable {
  public init() {}
}
