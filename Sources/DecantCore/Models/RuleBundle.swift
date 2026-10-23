import Foundation

/// The signed delivery artifact, mirroring `dist/rules.bundle.json` and `bundle.schema.json` §5.
///
/// Decoding is **resilient per-rule**: the envelope fields are required, but a rule that fails to
/// decode (unknown matcher/action `type`, malformed selector, etc.) is *dropped* and recorded in
/// ``decodeDiagnostics`` rather than failing the whole bundle. This implements the §2 rule that an
/// old client meeting a forward-compatible rule keeps cleaning with the rules it understands.
///
/// Encoding emits only the four contract fields (``decodeDiagnostics`` is decode-time metadata),
/// so a round-trip of a fully-understood bundle is semantically identity.
public struct RuleBundle: Codable, Sendable {
  /// Schema major version. v1 = the current contract.
  public let schemaVersion: Int
  /// Monotonic publish counter used for anti-rollback (§5.2).
  public let generation: Int
  /// Informational ISO-8601 timestamp of when the bundle was compiled.
  public let generatedAt: String
  /// The rules that decoded successfully.
  public let rules: [Rule]
  /// Non-fatal findings about this bundle: rules dropped during decode (§2) and any load-time
  /// warning such as a `schemaVersion` newer than this engine supports. Not serialized.
  public let decodeDiagnostics: [RuleDiagnostic]

  private enum CodingKeys: String, CodingKey {
    case schemaVersion, generation, generatedAt, rules
  }

  /// Memberwise initializer (no diagnostics).
  public init(schemaVersion: Int, generation: Int, generatedAt: String, rules: [Rule]) {
    self.init(
      schemaVersion: schemaVersion, generation: generation, generatedAt: generatedAt, rules: rules,
      decodeDiagnostics: [])
  }

  init(
    schemaVersion: Int, generation: Int, generatedAt: String, rules: [Rule],
    decodeDiagnostics: [RuleDiagnostic]
  ) {
    self.schemaVersion = schemaVersion
    self.generation = generation
    self.generatedAt = generatedAt
    self.rules = rules
    self.decodeDiagnostics = decodeDiagnostics
  }

  /// Returns a copy with `extra` appended to ``decodeDiagnostics``. Used by the loader to attach
  /// load-time warnings (e.g. version skew) onto the decoded bundle.
  func appendingDiagnostics(_ extra: [RuleDiagnostic]) -> RuleBundle {
    guard !extra.isEmpty else { return self }
    return RuleBundle(
      schemaVersion: schemaVersion,
      generation: generation,
      generatedAt: generatedAt,
      rules: rules,
      decodeDiagnostics: decodeDiagnostics + extra
    )
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
    generation = try c.decode(Int.self, forKey: .generation)
    generatedAt = try c.decode(String.self, forKey: .generatedAt)

    // Decode each rule into a slot that captures failures instead of throwing, so one bad rule
    // never aborts the array. Each slot consumes exactly one element of the unkeyed container.
    let slots = try c.decode([RuleSlot].self, forKey: .rules)
    var accepted: [Rule] = []
    var diagnostics: [RuleDiagnostic] = []
    for slot in slots {
      switch slot.result {
      case .success(let rule):
        accepted.append(rule)
      case .failure(let error):
        diagnostics.append(
          RuleDiagnostic(
            ruleID: slot.id ?? "<unknown>",
            severity: .skippedRule,
            message: "dropped during decode: \(error)"
          )
        )
      }
    }
    rules = accepted
    decodeDiagnostics = diagnostics
  }

  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(schemaVersion, forKey: .schemaVersion)
    try c.encode(generation, forKey: .generation)
    try c.encode(generatedAt, forKey: .generatedAt)
    try c.encode(rules, forKey: .rules)
  }
}

/// Decodes a single rule element without throwing, capturing either the rule or its decode error.
///
/// Because this type's `init(from:)` never throws, decoding `[RuleSlot]` consumes the whole `rules`
/// array even when individual elements are malformed — giving per-rule resilience.
private struct RuleSlot: Decodable {
  let id: String?
  let result: Result<Rule, Error>

  private enum IDKeys: String, CodingKey { case id }

  init(from decoder: Decoder) throws {
    // Best-effort id for diagnostics, independent of whether the full rule decodes.
    id = try? decoder.container(keyedBy: IDKeys.self).decode(String.self, forKey: .id)
    result = Result { try Rule(from: decoder) }
  }
}
