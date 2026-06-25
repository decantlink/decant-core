import Foundation

/// The outcome of cleaning a single URL.
///
/// This is the consumer-facing contract the app and share extension depend on: a cleaned URL plus
/// an accounting of what was removed, used to drive the before/after "output moment" and the
/// tracker-count tick on the share sheet.
public struct CleanResult: Equatable, Sendable {
  /// The URL after tracking parameters were removed. Equal to the input when nothing matched.
  public let cleanedURL: URL

  /// The names of the query parameters that were removed, in their **original on-wire spelling**
  /// and original order (percent-encoded names are reported as they appeared in the URL).
  public let removedParameterNames: [String]

  /// Whether the engine changed the URL at all. `false` means `cleanedURL == input`.
  public let wasModified: Bool

  /// The number of parameters removed. Convenience over `removedParameterNames.count`.
  public var removedParameterCount: Int { removedParameterNames.count }

  /// Creates a result.
  /// - Parameters:
  ///   - cleanedURL: The URL after cleaning.
  ///   - removedParameterNames: Names of removed query parameters, in original order.
  ///   - wasModified: Whether the URL changed.
  public init(cleanedURL: URL, removedParameterNames: [String], wasModified: Bool) {
    self.cleanedURL = cleanedURL
    self.removedParameterNames = removedParameterNames
    self.wasModified = wasModified
  }

  /// A result representing "no change": the URL passed through untouched.
  /// - Parameter url: The unchanged URL.
  /// - Returns: A result with no removed parameters and `wasModified == false`.
  public static func unchanged(_ url: URL) -> CleanResult {
    CleanResult(cleanedURL: url, removedParameterNames: [], wasModified: false)
  }
}
