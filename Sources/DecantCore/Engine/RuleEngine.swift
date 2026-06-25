import Foundation

/// Removes tracking parameters from URLs.
///
/// This protocol is the stable seam between the app and the cleaning engine. The app talks
/// only to `RuleEngine` (wrapped as a TCA dependency), so the real, JSON-rule-driven engine
/// can replace any stub without any feature-layer changes.
///
/// Implementations must be deterministic and side-effect free: the same URL always yields
/// the same ``CleanResult``, and the URL never leaves the device.
public protocol RuleEngine: Sendable {
  /// Cleans a single URL by removing tracking parameters.
  /// - Parameter url: The URL to clean.
  /// - Returns: The cleaned URL plus an accounting of what was removed.
  func clean(_ url: URL) -> CleanResult
}
