import Foundation

/// A non-fatal note produced while decoding or validating a bundle.
///
/// Diagnostics are how the engine reports forward-compatibility decisions (`SCHEMA.md` §2) without
/// crashing: a rule it cannot understand is dropped and surfaced here rather than failing the whole
/// bundle. Callers may log these; they never block cleaning with the rules that *were* understood.
public struct RuleDiagnostic: Sendable, Equatable {
  /// How serious the finding is.
  public enum Severity: Sendable, Equatable {
    /// The rule was kept, but something about it is worth noting (e.g. `removeAllParameters`
    /// subsumes a sibling `removeParameters`).
    case warning
    /// The rule was dropped and does not participate in cleaning.
    case skippedRule
  }

  /// The `id` of the offending rule, or `"<unknown>"` if it could not be read.
  public let ruleID: String
  /// The severity of the finding.
  public let severity: Severity
  /// Human-readable explanation.
  public let message: String

  /// Creates a diagnostic.
  public init(ruleID: String, severity: Severity, message: String) {
    self.ruleID = ruleID
    self.severity = severity
    self.message = message
  }
}
