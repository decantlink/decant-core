import Foundation

/// Semantic validation of already-decoded rules.
///
/// Structural constraints (unknown matcher/action `type`, selector exactly-one-of) are enforced at
/// *decode* time — they are not representable in the Swift value model, so a decoded ``Rule`` is
/// already structurally sound. This validator covers the remaining semantic constraints that a
/// well-typed value can still violate:
///
/// - **Unanchored `hostRegex`** is rejected: an unanchored pattern like `amazon.*` would match
///   `amazon.com.phishing.ru` (`SCHEMA.md` §3). The pattern must be `^…$`.
/// - **Uncompilable `hostRegex`** is rejected (it can never match).
/// - **Degenerate `host`** with neither `exact` nor `suffix` literals is rejected (matches nothing).
/// - **`removeAllParameters` alongside `removeParameters`** earns a ``RuleDiagnostic/Severity/warning``
///   (the latter is subsumed), but the rule is kept.
public struct RuleValidator {
  /// Validates a list of rules.
  /// - Parameter rules: The decoded rules to check.
  /// - Returns: The rules that passed, plus diagnostics for every rejected rule and every warning.
  public static func validate(_ rules: [Rule]) -> (accepted: [Rule], diagnostics: [RuleDiagnostic]) {
    var accepted: [Rule] = []
    var diagnostics: [RuleDiagnostic] = []

    for rule in rules {
      if let rejection = rejectionReason(for: rule.matcher) {
        diagnostics.append(RuleDiagnostic(ruleID: rule.id, severity: .skippedRule, message: rejection))
        continue
      }
      if hasRedundantRemoveAll(rule.actions) {
        diagnostics.append(
          RuleDiagnostic(
            ruleID: rule.id,
            severity: .warning,
            message: "removeAllParameters subsumes the sibling removeParameters action(s)"
          )
        )
      }
      accepted.append(rule)
    }
    return (accepted, diagnostics)
  }

  /// Returns a rejection message if the matcher is semantically invalid, else `nil`.
  private static func rejectionReason(for matcher: Rule.Matcher) -> String? {
    switch matcher {
    case .any:
      return nil
    case .host(let exact, let suffix):
      return exact.isEmpty && suffix.isEmpty ? "host matcher has no exact or suffix literals" : nil
    case .hostRegex(let pattern):
      guard pattern.hasPrefix("^"), pattern.hasSuffix("$"), pattern.count >= 2 else {
        return "hostRegex pattern must be anchored (^…$): '\(pattern)'"
      }
      guard (try? NSRegularExpression(pattern: pattern)) != nil else {
        return "hostRegex pattern does not compile: '\(pattern)'"
      }
      return nil
    }
  }

  private static func hasRedundantRemoveAll(_ actions: [Rule.Action]) -> Bool {
    let hasRemoveAll = actions.contains { if case .removeAllParameters = $0 { true } else { false } }
    let hasRemoveParams = actions.contains { if case .removeParameters = $0 { true } else { false } }
    return hasRemoveAll && hasRemoveParams
  }
}
