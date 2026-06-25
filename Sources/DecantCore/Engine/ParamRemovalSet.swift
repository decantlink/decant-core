import Foundation

/// The folded parameter-removal criteria contributed by one or more rules.
///
/// Clean actions are commutative and batched (union of removals) across matching rules — except
/// `keepOnly`, which does not stack: the **highest-priority** (lowest `priority` number) matching
/// rule's allowlist wins (`SCHEMA.md` §4). This type folds a rule's actions and merges with other
/// folds while preserving those semantics.
struct ParamRemovalSet: Sendable {
  /// `removeAllParameters` was requested by some contributing rule.
  var removeAll = false
  /// Exact decoded names to remove.
  var names: Set<String> = []
  /// Decoded-name prefixes to remove.
  var prefixes: [String] = []
  /// Compiled `regex` selectors to match decoded names against.
  var regexes: [CompiledRegex] = []
  /// The winning `keepOnly` allowlist and the priority of the rule that supplied it.
  var keepOnly: (priority: Int, allow: Set<String>)?

  /// Folds one rule's actions into this set, using `rule.priority` to break `keepOnly` ties.
  mutating func fold(_ rule: Rule) {
    for action in rule.actions {
      switch action {
      case .removeAllParameters:
        removeAll = true
      case .removeParameters(let selector):
        switch selector {
        case .names(let value): names.formUnion(value)
        case .prefix(let value): prefixes.append(value)
        case .regex(let value): regexes.append(CompiledRegex(value))
        case .keepOnly(let value): adoptKeepOnly(priority: rule.priority, allow: Set(value))
        }
      }
    }
  }

  /// Merges another fold into this one. Used to combine the precomputed global set with the
  /// per-host folds at clean time. `keepOnly` keeps the lower-priority-number contributor.
  mutating func merge(_ other: ParamRemovalSet) {
    removeAll = removeAll || other.removeAll
    names.formUnion(other.names)
    prefixes.append(contentsOf: other.prefixes)
    regexes.append(contentsOf: other.regexes)
    if let incoming = other.keepOnly {
      adoptKeepOnly(priority: incoming.priority, allow: incoming.allow)
    }
  }

  private mutating func adoptKeepOnly(priority: Int, allow: Set<String>) {
    if let current = keepOnly {
      if priority < current.priority { keepOnly = (priority, allow) }
    } else {
      keepOnly = (priority, allow)
    }
  }

  /// Whether a parameter with the given **decoded** name should be removed.
  func removes(decodedName: String) -> Bool {
    if removeAll { return true }
    if names.contains(decodedName) { return true }
    for prefix in prefixes where decodedName.hasPrefix(prefix) { return true }
    for regex in regexes where regex.matches(decodedName) { return true }
    if let keepOnly, !keepOnly.allow.contains(decodedName) { return true }
    return false
  }

  /// Whether this set can remove anything at all (lets `clean` skip parsing when nothing applies).
  var isEmpty: Bool {
    !removeAll && names.isEmpty && prefixes.isEmpty && regexes.isEmpty && keepOnly == nil
  }
}
