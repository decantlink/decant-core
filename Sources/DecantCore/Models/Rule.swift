import Foundation

/// A single Decant cleaning rule, as authored in `decant-rules` and delivered in a signed bundle.
///
/// `Rule` is the faithful in-memory image of the `rule.schema.json` contract: a host matcher, an
/// ordered list of clean actions, and identity/metadata used for merging and diagnostics. The
/// nested ``Matcher``, ``Action`` and ``Selector`` types model the schema's tagged-union shapes.
///
/// Decoding is forward-compatible per `SCHEMA.md` §2: an unknown ``Matcher`` or ``Action`` `type`
/// causes the *enclosing rule* to fail decoding (so the bundle decoder can drop it whole rather
/// than partial-apply); an unknown value for the optional `category` field is ignored.
public struct Rule: Codable, Equatable, Sendable {
  /// Stable, namespaced merge key (e.g. `"shopping.amazon"`). Not a UUID — it survives re-authoring
  /// and is the key for broken-link reports and user overrides.
  public let id: String
  /// Human-readable rule name.
  public let name: String
  /// Optional longer description, including any source attribution.
  public let description: String?
  /// The host-scoping predicate that decides whether this rule applies to a URL.
  public let matcher: Matcher
  /// The ordered clean actions to apply when the matcher matches. v1 actions are commutative.
  public let actions: [Action]
  /// Relative precedence; **lower means higher priority**. Used to break `keepOnly` ties. Default 100.
  public let priority: Int
  /// Whether the rule participates in compilation. Default `true`.
  public let enabled: Bool
  /// Where the rule originated.
  public let source: Source
  /// Optional taxonomy bucket. An unrecognized value decodes to `nil` (the field is ignored).
  public let category: Category?
  /// Per-rule version for future sync conflict resolution. Default 1.
  public let version: Int

  /// Creates a rule. Mirrors the schema defaults so call sites and decode share one shape.
  public init(
    id: String,
    name: String,
    description: String? = nil,
    matcher: Matcher,
    actions: [Action],
    priority: Int = 100,
    enabled: Bool = true,
    source: Source,
    category: Category? = nil,
    version: Int = 1
  ) {
    self.id = id
    self.name = name
    self.description = description
    self.matcher = matcher
    self.actions = actions
    self.priority = priority
    self.enabled = enabled
    self.source = source
    self.category = category
    self.version = version
  }

  /// Host-scoping predicate. Tagged union: `any` | `host` | `hostRegex`.
  public enum Matcher: Codable, Equatable, Sendable {
    /// Matches every URL. Folded into the global parameter-removal index at compile time.
    case any
    /// Label-boundary host match. `exact` requires `H == D`; `suffix` requires `H == D` or
    /// `H` ends with `"." + D`. A matcher carries at least one of the two lists.
    case host(exact: [String], suffix: [String])
    /// Anchored host-regex escape hatch (validated to be `^…$` by ``RuleValidator``).
    case hostRegex(String)
  }

  /// A clean-phase action. v1 tagged union: `removeParameters` | `removeAllParameters`.
  public enum Action: Codable, Equatable, Sendable {
    /// Remove the query parameters selected by ``Selector``.
    case removeParameters(Selector)
    /// Remove every query parameter (subsumes any `removeParameters` in scope).
    case removeAllParameters
  }

  /// Query-parameter selector. **Exactly one** case is present in any valid rule.
  public enum Selector: Codable, Equatable, Sendable {
    /// Remove parameters whose decoded name is in this set.
    case names([String])
    /// Remove parameters whose decoded name has this prefix.
    case prefix(String)
    /// Remove parameters whose decoded name matches this anchored-or-not regex.
    case regex(String)
    /// Keep only parameters whose decoded name is in this allowlist; remove the rest. Does not stack.
    case keepOnly([String])
  }

  /// Provenance of a rule.
  public enum Source: String, Codable, Sendable {
    case builtIn, user, community, ai
  }

  /// Taxonomy bucket for a rule.
  public enum Category: String, Codable, Sendable {
    case tracking, affiliate, session, analytics, social, shopping, advertising, urlRewriting, appRouting, custom
  }

  private enum CodingKeys: String, CodingKey {
    case id, name, description, matcher, actions, priority, enabled, source, category, version
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decode(String.self, forKey: .id)
    name = try c.decode(String.self, forKey: .name)
    description = try c.decodeIfPresent(String.self, forKey: .description)
    matcher = try c.decode(Matcher.self, forKey: .matcher)
    actions = try c.decode([Action].self, forKey: .actions)
    priority = try c.decodeIfPresent(Int.self, forKey: .priority) ?? 100
    enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    source = try c.decode(Source.self, forKey: .source)
    // Unknown category value is an unknown optional-field value → ignore it, keep the rule (§2).
    category = (try? c.decode(Category.self, forKey: .category)) ?? nil
    version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
  }

  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(id, forKey: .id)
    try c.encode(name, forKey: .name)
    try c.encodeIfPresent(description, forKey: .description)
    try c.encode(matcher, forKey: .matcher)
    try c.encode(actions, forKey: .actions)
    try c.encode(priority, forKey: .priority)
    try c.encode(enabled, forKey: .enabled)
    try c.encode(source, forKey: .source)
    try c.encodeIfPresent(category, forKey: .category)
    try c.encode(version, forKey: .version)
  }
}
