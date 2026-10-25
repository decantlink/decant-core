import Foundation
import Testing

@testable import DecantCore

/// Gate 1: Models + Codable — tagged-union decode, semantic round-trip, unknown-element skip.
struct ModelDecodingTests {
  private func loadSeedBundleData() throws -> Data {
    let url = try #require(Bundle.module.url(forResource: "rules.bundle", withExtension: "json"))
    return try Data(contentsOf: url)
  }

  @Test func decodesSeedBundleToNineRules() throws {
    let bundle = try JSONDecoder().decode(RuleBundle.self, from: loadSeedBundleData())
    #expect(bundle.schemaVersion == 1)
    #expect(bundle.generation == 1)
    #expect(bundle.rules.count == 9)
    #expect(bundle.decodeDiagnostics.isEmpty)
    #expect(
      bundle.rules.map(\.id) == [
        "tracking.utm", "tracking.click-ids", "social.twitter", "social.instagram",
        "social.instagram-web",
        "social.facebook", "social.tiktok", "social.youtube", "shopping.amazon",
      ])
  }

  @Test func taggedUnionsDecodeToExpectedCases() throws {
    let bundle = try JSONDecoder().decode(RuleBundle.self, from: loadSeedBundleData())
    let byID = Dictionary(uniqueKeysWithValues: bundle.rules.map { ($0.id, $0) })

    #expect(byID["tracking.utm"]?.matcher == .any)
    #expect(byID["tracking.utm"]?.actions == [.removeParameters(.prefix("utm_"))])
    #expect(
      byID["social.youtube"]?.actions == [
        .removeParameters(.keepOnly(["v", "t", "list", "index"]))
      ])

    if case .host(let exact, let suffix) = byID["social.twitter"]?.matcher {
      #expect(exact.isEmpty)
      #expect(suffix == ["twitter.com", "x.com"])
    } else {
      Issue.record("expected host matcher")
    }

    // Defaults applied where the JSON omits them.
    #expect(byID["tracking.utm"]?.priority == 100)
    #expect(byID["tracking.utm"]?.enabled == true)
    #expect(byID["tracking.utm"]?.version == 1)
  }

  @Test func semanticRoundTrip() throws {
    let decoder = JSONDecoder()
    let original = try decoder.decode(RuleBundle.self, from: loadSeedBundleData())
    let reEncoded = try JSONEncoder().encode(original)
    let reDecoded = try decoder.decode(RuleBundle.self, from: reEncoded)
    #expect(reDecoded.rules == original.rules)
    #expect(reDecoded.schemaVersion == original.schemaVersion)
    #expect(reDecoded.generation == original.generation)
  }

  @Test func unknownMatcherTypeDropsRuleWithDiagnostic() throws {
    let json = """
      { "schemaVersion": 1, "generation": 2, "generatedAt": "2026-06-24T00:00:00Z", "rules": [
        { "id": "good.rule", "name": "ok", "matcher": { "type": "any" },
          "actions": [ { "type": "removeAllParameters" } ], "source": "builtIn" },
        { "id": "future.matcher", "name": "v2", "matcher": { "type": "pathPattern", "glob": "/x/*" },
          "actions": [ { "type": "removeAllParameters" } ], "source": "builtIn" }
      ] }
      """
    let bundle = try JSONDecoder().decode(RuleBundle.self, from: Data(json.utf8))
    #expect(bundle.rules.map(\.id) == ["good.rule"])
    #expect(bundle.decodeDiagnostics.count == 1)
    #expect(bundle.decodeDiagnostics.first?.ruleID == "future.matcher")
    #expect(bundle.decodeDiagnostics.first?.severity == .skippedRule)
  }

  @Test func hostPathRoundTrips() throws {
    let json = """
      { "id": "a.b", "name": "share paths", "source": "builtIn",
        "matcher": { "type": "hostPath", "exact": ["instagram.com"], "suffix": ["example.com"],
                     "path": { "prefix": ["/reel", "/p/"] } },
        "actions": [ { "type": "removeAllParameters" } ] }
      """
    let rule = try JSONDecoder().decode(Rule.self, from: Data(json.utf8))
    let expected = Rule.Matcher.hostPath(
      exact: ["instagram.com"], suffix: ["example.com"], pathPrefixes: ["/reel", "/p/"])
    #expect(rule.matcher == expected)

    let encoded = try JSONEncoder().encode(rule)
    let object = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    let matcher = try #require(object["matcher"] as? [String: Any])
    #expect(matcher["type"] as? String == "hostPath")
    #expect((matcher["path"] as? [String: Any])?["prefix"] as? [String] == ["/reel", "/p/"])
    #expect(try JSONDecoder().decode(Rule.self, from: encoded) == rule)
  }

  @Test(arguments: [
    #"{ "type": "hostPath", "exact": ["a.com"] }"#,
    #"{ "type": "hostPath", "exact": ["a.com"], "path": {} }"#,
    #"{ "type": "hostPath", "exact": ["a.com"], "path": { "prefix": ["/r"], "pattern": "^/r$" } }"#,
  ])
  func malformedHostPathDropsRuleWithDiagnostic(matcherJSON: String) throws {
    let json = """
      { "schemaVersion": 1, "generation": 2, "generatedAt": "2026-06-24T00:00:00Z", "rules": [
        { "id": "bad.path", "name": "x", "matcher": \(matcherJSON),
          "actions": [ { "type": "removeAllParameters" } ], "source": "builtIn" }
      ] }
      """
    let bundle = try JSONDecoder().decode(RuleBundle.self, from: Data(json.utf8))
    #expect(bundle.rules.isEmpty)
    #expect(bundle.decodeDiagnostics.first?.ruleID == "bad.path")
    #expect(bundle.decodeDiagnostics.first?.severity == .skippedRule)
  }

  @Test func unknownActionTypeDropsRuleWithDiagnostic() throws {
    let json = """
      { "schemaVersion": 1, "generation": 2, "generatedAt": "2026-06-24T00:00:00Z", "rules": [
        { "id": "future.action", "name": "v2", "matcher": { "type": "any" },
          "actions": [ { "type": "redirect", "to": "https://x" } ], "source": "builtIn" }
      ] }
      """
    let bundle = try JSONDecoder().decode(RuleBundle.self, from: Data(json.utf8))
    #expect(bundle.rules.isEmpty)
    #expect(bundle.decodeDiagnostics.first?.ruleID == "future.action")
  }

  @Test func multiKeySelectorDropsRuleWithDiagnostic() throws {
    let json = """
      { "schemaVersion": 1, "generation": 2, "generatedAt": "2026-06-24T00:00:00Z", "rules": [
        { "id": "bad.selector", "name": "two keys", "matcher": { "type": "any" },
          "actions": [ { "type": "removeParameters", "select": { "names": ["a"], "prefix": "b" } } ],
          "source": "builtIn" }
      ] }
      """
    let bundle = try JSONDecoder().decode(RuleBundle.self, from: Data(json.utf8))
    #expect(bundle.rules.isEmpty)
    #expect(bundle.decodeDiagnostics.first?.ruleID == "bad.selector")
    #expect(bundle.decodeDiagnostics.first?.severity == .skippedRule)
  }

  @Test func unknownOptionalFieldKeepsRule() throws {
    // Unknown category value and an unknown extra field: rule is kept; category ignored.
    let json = """
      { "schemaVersion": 1, "generation": 2, "generatedAt": "2026-06-24T00:00:00Z", "rules": [
        { "id": "fwd.compat", "name": "ok", "matcher": { "type": "any" },
          "actions": [ { "type": "removeAllParameters" } ], "source": "builtIn",
          "category": "quantumTracking", "futureField": 42 }
      ] }
      """
    let bundle = try JSONDecoder().decode(RuleBundle.self, from: Data(json.utf8))
    #expect(bundle.rules.map(\.id) == ["fwd.compat"])
    #expect(bundle.rules.first?.category == nil)
    #expect(bundle.decodeDiagnostics.isEmpty)
  }
}
