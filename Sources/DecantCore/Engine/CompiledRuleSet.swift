import Foundation

/// The compiled, ready-to-run cleaning engine. Holds the two runtime indices and *is* the
/// ``RuleEngine``: there is no separate object to wire.
///
/// Matching is O(params), not a scan over all rules:
/// - `global` is the fold of every `any` rule (computed once).
/// - `bySuffix` / `byExact` map each declared host literal to the rules registered under it; a URL's
///   host is matched by probing its ≤~4 label-suffixes (plus an exact probe), never the whole map.
/// - `hostRegexRules` is the small, audited list matched linearly.
///
/// Cleaning is a **surgical splice** on the raw query substring (see ``URLParts``); kept parameters
/// keep their original bytes, only matched pairs and their separators are excised.
public struct CompiledRuleSet: Sendable, RuleEngine {
  private let global: ParamRemovalSet
  private let bySuffix: [String: [CompiledRule]]
  private let byExact: [String: [CompiledRule]]
  private let hostRegexRules: [(regex: CompiledRegex, rule: CompiledRule)]

  init(
    global: ParamRemovalSet,
    bySuffix: [String: [CompiledRule]],
    byExact: [String: [CompiledRule]],
    hostRegexRules: [(regex: CompiledRegex, rule: CompiledRule)]
  ) {
    self.global = global
    self.bySuffix = bySuffix
    self.byExact = byExact
    self.hostRegexRules = hostRegexRules
  }

  public func clean(_ url: URL) -> CleanResult {
    let parts = URLParts(url.absoluteString)
    guard let rawQuery = parts.rawQuery, !rawQuery.isEmpty else { return .unchanged(url) }

    // Gather the removal criteria that apply to this URL's host (global first, then host-scoped).
    var removals = global
    if let host = url.host(percentEncoded: false)?.lowercased() {
      var seen = Set<String>()
      func consider(_ compiled: CompiledRule) {
        if seen.insert(compiled.id).inserted { removals.merge(compiled.removal) }
      }
      byExact[host]?.forEach(consider)
      for suffix in Self.labelSuffixes(of: host) {
        bySuffix[suffix]?.forEach(consider)
      }
      for entry in hostRegexRules where entry.regex.matches(host) { consider(entry.rule) }
    }
    guard !removals.isEmpty else { return .unchanged(url) }

    // Split on '&' only — ';' is not a separator (WHATWG). Tokens stay byte-verbatim.
    var keptTokens: [Substring] = []
    var removedNames: [String] = []
    for token in rawQuery.split(separator: "&", omittingEmptySubsequences: false) {
      // An empty token (from "&&" or a trailing "&") is not a parameter — keep it byte-verbatim.
      if token.isEmpty {
        keptTokens.append(token)
        continue
      }
      let onWireName = token.firstIndex(of: "=").map { token[..<$0] } ?? token
      let decodedName = String(onWireName).removingPercentEncoding ?? String(onWireName)
      if removals.removes(decodedName: decodedName) {
        removedNames.append(String(onWireName))
      } else {
        keptTokens.append(token)
      }
    }

    guard !removedNames.isEmpty else { return .unchanged(url) }
    let rebuilt = parts.reassembled(keptTokens: keptTokens)
    // A spliced remainder that no longer parses must not masquerade as a modified result.
    guard let cleaned = URL(string: rebuilt) else { return .unchanged(url) }
    return CleanResult(cleanedURL: cleaned, removedParameterNames: removedNames, wasModified: true)
  }

  /// The label-boundary suffixes of a host, longest first: `www.amazon.co.uk` →
  /// `[www.amazon.co.uk, amazon.co.uk, co.uk, uk]`. Probing these against `bySuffix` realizes the
  /// §3 rule "`D` matches `H` iff `H == D` or `H` ends with `.D`" without a Public Suffix List.
  static func labelSuffixes(of host: String) -> [String] {
    let labels = host.split(separator: ".", omittingEmptySubsequences: false)
    guard labels.count > 1 else { return [host] }
    return (0..<labels.count).map { labels[$0...].joined(separator: ".") }
  }
}
