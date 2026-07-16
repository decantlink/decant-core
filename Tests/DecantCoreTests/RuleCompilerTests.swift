import Foundation
import Testing
@testable import DecantCore

struct RuleCompilerTests {
  @Test func authoredHostCaseIsNormalized() throws {
    let rule = Rule(
      id: "test.case-normalization",
      name: "Mixed-case host literals",
      matcher: .host(exact: ["Example.COM"], suffix: ["Amazon.Com"]),
      actions: [.removeParameters(.names(["tag"]))],
      source: .builtIn
    )
    let engine = RuleCompiler.compile([rule])

    let exact = engine.clean(try #require(URL(string: "https://example.com/p?tag=x&q=1")))
    #expect(exact.cleanedURL.absoluteString == "https://example.com/p?q=1")
    #expect(exact.removedParameterNames == ["tag"])

    let suffix = engine.clean(try #require(URL(string: "https://www.amazon.com/p?tag=x&q=1")))
    #expect(suffix.cleanedURL.absoluteString == "https://www.amazon.com/p?q=1")
    #expect(suffix.removedParameterNames == ["tag"])
  }
}
