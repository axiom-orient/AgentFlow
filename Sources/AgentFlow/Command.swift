/// Stable product identity for cancellable command work.
public struct CancellationID: RawRepresentable, Hashable, Sendable, Codable,
  ExpressibleByStringLiteral, CustomStringConvertible
{
  public let rawValue: String

  public init(rawValue: String) {
    precondition(!rawValue.isEmpty, "CancellationID must not be empty")
    self.rawValue = rawValue
  }

  public init(stringLiteral value: StringLiteralType) {
    self.init(rawValue: value)
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    let value = try container.decode(String.self)
    guard !value.isEmpty else {
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "CancellationID must not be empty")
    }
    rawValue = value
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }

  public var description: String { rawValue }
}

/// Runtime ownership policy for one typed command operation.
public enum CommandPolicy: Sendable, Equatable, Codable {
  /// Run independently. The store cancels it on `cancelAll()` or teardown.
  case concurrent

  /// Cancel the current generation for the identifier, then start this operation.
  case cancelInFlight(CancellationID)

  /// Ignore this operation while the identifier already has live work.
  case dropIfRunning(CancellationID)
}

/// A pure value emitted by a reducer to describe work outside the reducer.
public enum Command<Operation: Sendable>: Sendable {
  case run(Operation, policy: CommandPolicy = .concurrent)
  case cancel(CancellationID)

  /// Lifts a child operation into its parent's operation without changing lifetime policy.
  public func map<Parent: Sendable>(_ transform: (Operation) -> Parent) -> Command<Parent> {
    switch self {
    case .run(let operation, let policy): .run(transform(operation), policy: policy)
    case .cancel(let id): .cancel(id)
    }
  }
}

extension Command: Equatable where Operation: Equatable {}
extension Command: Codable where Operation: Codable {}
