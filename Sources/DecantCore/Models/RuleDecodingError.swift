import Foundation

/// Structural decode failures that cause a whole rule to be dropped (never partial-applied).
///
/// These map to `SCHEMA.md` §2: an unknown matcher/action `type` or a malformed selector means the
/// rule cannot be safely understood, so the bundle decoder skips it and records a
/// ``RuleDiagnostic`` of severity ``RuleDiagnostic/Severity/skippedRule``.
enum RuleDecodingError: Error, CustomStringConvertible {
  /// The `matcher.type` is not one this engine version understands.
  case unknownMatcherType(String)
  /// An `action.type` is not one this engine version understands.
  case unknownActionType(String)
  /// A `select` object did not contain exactly one of `names`/`prefix`/`regex`/`keepOnly`.
  case invalidSelector
  /// A `hostPath` matcher's `path` object has a key this engine version does not understand.
  case unknownPathKey(String)

  var description: String {
    switch self {
    case .unknownMatcherType(let t): "unknown matcher type '\(t)'"
    case .unknownActionType(let t): "unknown action type '\(t)'"
    case .unknownPathKey(let k): "unknown hostPath path key '\(k)'"
    case .invalidSelector: "selector must contain exactly one of names/prefix/regex/keepOnly"
    }
  }
}
