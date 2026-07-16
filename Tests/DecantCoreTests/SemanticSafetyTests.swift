import Foundation
import Testing
@testable import DecantCore

/// Rule-data QA: cleaning must never change what the recipient sees. Splice mechanics are covered
/// by `URLFidelityTests`; this corpus (`fixtures/semantic-safety.json`) pins the functional
/// parameters the shipped rules must never strip.
struct SemanticSafetyTests {
  private struct Corpus: Decodable {
    struct Case: Decodable {
      let name: String
      let input: String
      let expected: String
      let removed: [String]
      let modified: Bool
    }
    let cases: [Case]
  }

  private func makeEngine() throws -> CompiledRuleSet {
    let url = try #require(Bundle.module.url(forResource: "rules.bundle", withExtension: "json"))
    let bundle = try JSONDecoder().decode(RuleBundle.self, from: Data(contentsOf: url))
    let (accepted, _) = RuleValidator.validate(bundle.rules)
    return RuleCompiler.compile(accepted)
  }

  @Test func rulesPreserveFunctionalParameters() throws {
    let engine = try makeEngine()
    let url = try #require(Bundle.module.url(forResource: "semantic-safety", withExtension: "json"))
    let cases = try JSONDecoder().decode(Corpus.self, from: Data(contentsOf: url)).cases
    for testCase in cases {
      let input = try #require(URL(string: testCase.input), "bad fixture URL: \(testCase.name)")
      let result = engine.clean(input)
      #expect(result.cleanedURL.absoluteString == testCase.expected, "url mismatch: \(testCase.name)")
      #expect(result.wasModified == testCase.modified, "modified mismatch: \(testCase.name)")
      #expect(result.removedParameterNames == testCase.removed, "removed mismatch: \(testCase.name)")
    }
  }
}
