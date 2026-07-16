import Foundation

/// Compiles validated rules into the in-memory ``CompiledRuleSet`` used at runtime.
///
/// Compilation happens **once** (the share extension builds the engine and holds it); it is never
/// repeated per `clean`. Rules are bucketed into the two indices the runtime matcher needs — a
/// global fold and a host map — so matching is O(params), not a linear scan over every rule.
public struct RuleCompiler {
  /// Compiles the given rules. Disabled rules are skipped.
  /// - Parameter rules: Rules to compile (typically the `accepted` output of ``RuleValidator``).
  /// - Returns: A ready-to-use engine.
  public static func compile(_ rules: [Rule]) -> CompiledRuleSet {
    var global = ParamRemovalSet()
    var bySuffix: [String: [CompiledRule]] = [:]
    var byExact: [String: [CompiledRule]] = [:]
    var hostRegexRules: [(regex: CompiledRegex, rule: CompiledRule)] = []

    for rule in rules where rule.enabled {
      switch rule.matcher {
      case .any:
        global.fold(rule)
      case .host(let exact, let suffix):
        let compiled = CompiledRule(rule)
        // clean() probes with a lowercased URL host; normalize authored literals to match.
        for host in exact { byExact[host.lowercased(), default: []].append(compiled) }
        for host in suffix { bySuffix[host.lowercased(), default: []].append(compiled) }
      case .hostRegex(let pattern):
        hostRegexRules.append((CompiledRegex(pattern), CompiledRule(rule)))
      }
    }

    return CompiledRuleSet(
      global: global,
      bySuffix: bySuffix,
      byExact: byExact,
      hostRegexRules: hostRegexRules
    )
  }
}

/// A host-scoped rule reduced to its identity and precomputed removal fold.
///
/// Folding each rule once at compile time keeps its ``CompiledRegex`` instances stable (so their
/// lazy compilation caches persist across cleans) and makes clean-time matching a cheap set merge.
struct CompiledRule: Sendable {
  let id: String
  let removal: ParamRemovalSet

  init(_ rule: Rule) {
    id = rule.id
    var set = ParamRemovalSet()
    set.fold(rule)
    removal = set
  }
}
