import Foundation

// MARK: Tagged-union Codable for the nested rule value types.
//
// The schema encodes each union as `{ "type": <tag>, … }` (matcher/action) or an exactly-one-of
// object (selector). Synthesized Codable cannot express these shapes, so each is hand-written.

extension Rule.Matcher {
  private enum CodingKeys: String, CodingKey { case type, exact, suffix, pattern }

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
