import Foundation
import Testing

@testable import DecantCore

/// Gate 2: RuleValidator — semantic rejection of unanchored/uncompilable hostRegex and degenerate
/// host matchers; redundant removeAll warns but keeps the rule.
struct RuleValidatorTests {
  private func rule(
    id: String, matcher: Rule.Matcher, actions: [Rule.Action] = [.removeAllParameters]
  ) -> Rule {
    Rule(id: id, name: id, matcher: matcher, actions: actions, source: .builtIn)
  }

  @Test func unanchoredHostRegexRejected() {
    let rules = [rule(id: "a.b", matcher: .hostRegex("amazon.*"))]
    let (accepted, diagnostics) = RuleValidator.validate(rules)
    #expect(accepted.isEmpty)
    #expect(diagnostics.count == 1)
    #expect(diagnostics.first?.severity == .skippedRule)
    #expect(diagnostics.first?.ruleID == "a.b")
  }

  @Test func anchoredHostRegexAccepted() {
    let rules = [rule(id: "a.b", matcher: .hostRegex("^(.*\\.)?amazon\\.[a-z.]+$"))]
    let (accepted, diagnostics) = RuleValidator.validate(rules)
    #expect(accepted.count == 1)
    #expect(diagnostics.isEmpty)
  }

  @Test func uncompilableHostRegexRejected() {
    let rules = [rule(id: "a.b", matcher: .hostRegex("^([a-z$"))]
    let (accepted, _) = RuleValidator.validate(rules)
    #expect(accepted.isEmpty)
  }

  @Test func degenerateHostRejected() {
    let rules = [rule(id: "a.b", matcher: .host(exact: [], suffix: []))]
    let (accepted, diagnostics) = RuleValidator.validate(rules)
    #expect(accepted.isEmpty)
    #expect(diagnostics.first?.severity == .skippedRule)
  }

  @Test func redundantRemoveAllWarnsButKeeps() {
    let rules = [
      rule(
        id: "a.b", matcher: .any,
        actions: [.removeAllParameters, .removeParameters(.prefix("utm_"))])
    ]
    let (accepted, diagnostics) = RuleValidator.validate(rules)
    #expect(accepted.count == 1)
    #expect(diagnostics.count == 1)
    #expect(diagnostics.first?.severity == .warning)
  }

  @Test func seedBundleValidatesClean() throws {
    let url = try #require(Bundle.module.url(forResource: "rules.bundle", withExtension: "json"))
    let bundle = try JSONDecoder().decode(RuleBundle.self, from: Data(contentsOf: url))
    let (accepted, diagnostics) = RuleValidator.validate(bundle.rules)
    #expect(accepted.count == 9)
    #expect(diagnostics.isEmpty)
  }
}
