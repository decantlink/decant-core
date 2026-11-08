import Foundation
import Testing

@testable import DecantCore

/// `QueryParameters` is the engine's only tokenizer and splicer: it must reproduce `clean` exactly
/// and rebuild any omit set byte-verbatim.
struct QueryParametersTests {
  private struct Corpus: Decodable {
    struct Case: Decodable {
      let name: String
      let input: String
    }
    let cases: [Case]
  }

  private func loadCases(_ resource: String) throws -> [Corpus.Case] {
    let url = try #require(Bundle.module.url(forResource: resource, withExtension: "json"))
    return try JSONDecoder().decode(Corpus.self, from: Data(contentsOf: url)).cases
  }

  private func makeEngine() throws -> CompiledRuleSet {
    let url = try #require(Bundle.module.url(forResource: "rules.bundle", withExtension: "json"))
    let bundle = try JSONDecoder().decode(RuleBundle.self, from: Data(contentsOf: url))
    let (accepted, _) = RuleValidator.validate(bundle.rules)
    return RuleCompiler.compile(accepted)
  }

  private func ruleRemovedIndices(_ query: QueryParameters, _ result: CleanResult) -> Set<Int> {
    let removed = Set(result.removedParameterNames)
    return Set(query.parameters.filter { removed.contains($0.onWireName) }.map(\.index))
  }

  @Test(arguments: ["url-fidelity", "semantic-safety"])
  func omittingRuleRemovedTokensReproducesClean(corpus: String) throws {
    let engine = try makeEngine()
    for testCase in try loadCases(corpus) {
      let url = try #require(URL(string: testCase.input), "bad fixture URL: \(testCase.name)")
      let result = engine.clean(url)
      let query = QueryParameters(url)
      let omitted = ruleRemovedIndices(query, result)
      #expect(
        query.url(omitting: omitted)?.absoluteString == result.cleanedURL.absoluteString,
        "parity mismatch: \(testCase.name)")
      // No kept token shares an on-wire name with a removed one, so the name mapping is exact.
      #expect(omitted.count == result.removedParameterCount, "mapping mismatch: \(testCase.name)")
    }
  }

  @Test func parametersAreVerbatimNonEmptyTokens() throws {
    let url = try #require(
      URL(string: "https://e.com/p?utm%5Fsource=x&&flag&q=a+b&a=1;b=2&#f?z=1"))
    #expect(
      QueryParameters(url).parameters == [
        .init(
          index: 0, onWireName: "utm%5Fsource", decodedName: "utm_source", raw: "utm%5Fsource=x"),
        .init(index: 1, onWireName: "flag", decodedName: "flag", raw: "flag"),
        .init(index: 2, onWireName: "q", decodedName: "q", raw: "q=a+b"),
        .init(index: 3, onWireName: "a", decodedName: "a", raw: "a=1;b=2"),
      ])
  }

  @Test(arguments: [
    ("https://e.com/p?a=1&b=2&c=3", [0], "https://e.com/p?b=2&c=3"),
    ("https://e.com/p?a=1&b=2&c=3", [1], "https://e.com/p?a=1&c=3"),
    ("https://e.com/p?a=1&b=2&c=3", [2], "https://e.com/p?a=1&b=2"),
    ("https://e.com/p?a=1&b=2&c=3", [0, 1, 2], "https://e.com/p"),
    ("https://e.com/p?a=1&b=2#frag", [0, 1], "https://e.com/p#frag"),
    ("https://e.com/p?a=1&&b=2", [0], "https://e.com/p?&b=2"),
    ("https://e.com/p?a=1&&b=2", [0, 1], "https://e.com/p?"),
    ("https://e.com/p?a=1&&&b=2", [0, 1], "https://e.com/p?&"),
    ("https://e.com/p?a=1&b=2&", [1], "https://e.com/p?a=1&"),
    ("https://e.com/p?a=1&", [0], "https://e.com/p?"),
    ("https://e.com/p?q=a+b&x=1", [1], "https://e.com/p?q=a+b"),
    ("https://e.com/p?x=1&q=a+b%20c", [0], "https://e.com/p?q=a+b%20c"),
    ("https://e.com/p?x=1&y=2#sec?a=1&b=2", [0], "https://e.com/p?y=2#sec?a=1&b=2"),
    ("https://e.com/p#sec?a=1", [0], "https://e.com/p#sec?a=1"),
    ("https://e.com/p?a=&b=2&c", [1], "https://e.com/p?a=&c"),
    ("https://e.com/p?a=1&a=2&a=3", [1], "https://e.com/p?a=1&a=3"),
    ("https://e.com/p?utm%5Fsource=x&q=%E2%9C%93", [0], "https://e.com/p?q=%E2%9C%93"),
    ("https://e.com/p?a=1;b=2&c=3", [0], "https://e.com/p?c=3"),
  ])
  func splicesArbitraryOmitSetsVerbatim(input: String, omit: [Int], expected: String) throws {
    let query = QueryParameters(try #require(URL(string: input)))
    #expect(query.url(omitting: Set(omit))?.absoluteString == expected)
  }

  @Test(arguments: [
    "https://e.com/p",
    "https://e.com/p?",
    "https://e.com/p#f?x=1",
    "https://e.com/p?&&",
    "https://e.com/p?a=1&&b=+%20&#f?x",
  ])
  func omittingNothingReturnsOriginal(input: String) throws {
    let url = try #require(URL(string: input))
    let query = QueryParameters(url)
    #expect(query.url(omitting: []) == url)
    #expect(query.url(omitting: [-1, query.parameters.count]) == url)
    #expect(query.url(omitting: [])?.absoluteString == input)
  }

  private static func rule(_ actions: [Rule.Action]) -> Rule {
    Rule(
      id: "test.rule", name: "test.rule", matcher: .host(exact: [], suffix: ["example.com"]),
      actions: actions, source: .builtIn)
  }

  @Test(arguments: [
    (
      rule([.removeParameters(.names(["fbclid"]))]),
      "https://example.com/p?fbclid=A&q=2&fbclid=B", 0, "https://example.com/p?fbclid=A&q=2"
    ),
    (
      rule([.removeParameters(.prefix("utm_"))]),
      "https://example.com/p?utm_source=a&q=1&utm_medium=b", 2,
      "https://example.com/p?q=1&utm_medium=b"
    ),
    (
      rule([.removeParameters(.regex("^mc_(cid|eid)$"))]),
      "https://example.com/p?mc_cid=1&id=7&mc_eid=2", 0, "https://example.com/p?mc_cid=1&id=7"
    ),
    (
      rule([.removeParameters(.keepOnly(["v"]))]),
      "https://example.com/watch?v=abc&si=XYZ&t=10", 2, "https://example.com/watch?v=abc&t=10"
    ),
    (
      rule([.removeAllParameters]),
      "https://example.com/p?a=1&b=2#f", 1, "https://example.com/p?b=2#f"
    ),
  ])
  func restoresTokenRemovedBySelector(
    rule: Rule, input: String, restore: Int, expected: String
  ) throws {
    let url = try #require(URL(string: input))
    let result = RuleCompiler.compile([rule]).clean(url)
    let query = QueryParameters(url)
    let omitted = ruleRemovedIndices(query, result)
    #expect(omitted.contains(restore))
    #expect(query.url(omitting: omitted) == result.cleanedURL)
    #expect(query.url(omitting: omitted.subtracting([restore]))?.absoluteString == expected)
  }
}
