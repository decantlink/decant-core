import Foundation

// MARK: Tagged-union Codable for the nested rule value types.
//
// The schema encodes each union as `{ "type": <tag>, … }` (matcher/action) or an exactly-one-of
// object (selector). Synthesized Codable cannot express these shapes, so each is hand-written.

extension Rule.Matcher {
  private enum CodingKeys: String, CodingKey { case type, exact, suffix, path, pattern }

  /// Accepts any key so `init(from:)` can see, and reject, keys it does not know inside `path`.
  private struct PathKey: CodingKey {
    static let prefix = PathKey(stringValue: "prefix")
    let stringValue: String
    var intValue: Int? { nil }
    init(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    let type = try c.decode(String.self, forKey: .type)
    switch type {
    case "any":
      self = .any
    case "host":
      let exact = try c.decodeIfPresent([String].self, forKey: .exact) ?? []
      let suffix = try c.decodeIfPresent([String].self, forKey: .suffix) ?? []
      self = .host(exact: exact, suffix: suffix)
    case "hostPath":
      let exact = try c.decodeIfPresent([String].self, forKey: .exact) ?? []
      let suffix = try c.decodeIfPresent([String].self, forKey: .suffix) ?? []
      let path = try c.nestedContainer(keyedBy: PathKey.self, forKey: .path)
      // An unknown path key may narrow scope in a newer schema; ignoring it would widen the rule.
      if let unknown = path.allKeys.first(where: { $0.stringValue != PathKey.prefix.stringValue }) {
        throw RuleDecodingError.unknownPathKey(unknown.stringValue)
      }
      let prefixes = try path.decode([String].self, forKey: .prefix)
      self = .hostPath(exact: exact, suffix: suffix, pathPrefixes: prefixes)
    case "hostRegex":
      self = .hostRegex(try c.decode(String.self, forKey: .pattern))
    default:
      throw RuleDecodingError.unknownMatcherType(type)
    }
  }

  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .any:
      try c.encode("any", forKey: .type)
    case .host(let exact, let suffix):
      try c.encode("host", forKey: .type)
      if !exact.isEmpty { try c.encode(exact, forKey: .exact) }
      if !suffix.isEmpty { try c.encode(suffix, forKey: .suffix) }
    case .hostPath(let exact, let suffix, let pathPrefixes):
      try c.encode("hostPath", forKey: .type)
      if !exact.isEmpty { try c.encode(exact, forKey: .exact) }
      if !suffix.isEmpty { try c.encode(suffix, forKey: .suffix) }
      var path = c.nestedContainer(keyedBy: PathKey.self, forKey: .path)
      try path.encode(pathPrefixes, forKey: .prefix)
    case .hostRegex(let pattern):
      try c.encode("hostRegex", forKey: .type)
      try c.encode(pattern, forKey: .pattern)
    }
  }
}

extension Rule.Action {
  private enum CodingKeys: String, CodingKey { case type, select }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    let type = try c.decode(String.self, forKey: .type)
    switch type {
    case "removeParameters":
      self = .removeParameters(try c.decode(Rule.Selector.self, forKey: .select))
    case "removeAllParameters":
      self = .removeAllParameters
    default:
      throw RuleDecodingError.unknownActionType(type)
    }
  }

  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .removeParameters(let selector):
      try c.encode("removeParameters", forKey: .type)
      try c.encode(selector, forKey: .select)
    case .removeAllParameters:
      try c.encode("removeAllParameters", forKey: .type)
    }
  }
}

extension Rule.Selector {
  private enum CodingKeys: String, CodingKey { case names, prefix, regex, keepOnly }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    var found: Rule.Selector?
    func set(_ value: Rule.Selector) throws {
      guard found == nil else { throw RuleDecodingError.invalidSelector }
      found = value
    }
    if let v = try c.decodeIfPresent([String].self, forKey: .names) { try set(.names(v)) }
    if let v = try c.decodeIfPresent(String.self, forKey: .prefix) { try set(.prefix(v)) }
    if let v = try c.decodeIfPresent(String.self, forKey: .regex) { try set(.regex(v)) }
    if let v = try c.decodeIfPresent([String].self, forKey: .keepOnly) { try set(.keepOnly(v)) }
    guard let selector = found else { throw RuleDecodingError.invalidSelector }
    self = selector
  }

  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .names(let v): try c.encode(v, forKey: .names)
    case .prefix(let v): try c.encode(v, forKey: .prefix)
    case .regex(let v): try c.encode(v, forKey: .regex)
    case .keepOnly(let v): try c.encode(v, forKey: .keepOnly)
    }
  }
}
