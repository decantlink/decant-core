import Foundation
import Testing

@testable import DecantCore

/// `hostPath` matching: segment-boundary prefixes on the raw URL path, composed with host rules.
struct HostPathMatchingTests {
  private static func rule(
    _ id: String, _ matcher: Rule.Matcher, _ selector: Rule.Selector, priority: Int = 100
  ) -> Rule {
    Rule(
      id: id, name: id, matcher: matcher, actions: [.removeParameters(selector)],
      priority: priority, source: .builtIn)
  }

  private static func tagRule(prefixes: [String]) -> Rule {
    rule(
      "test.tag", .hostPath(exact: [], suffix: ["example.com"], pathPrefixes: prefixes),
      .names(["tag"]))
  }

  private static let instagramShare = rule(
    "test.instagram-share",
    .hostPath(
      exact: ["instagram.com", "www.instagram.com"], suffix: [],
      pathPrefixes: ["/reel", "/reels", "/p", "/tv"]),
    .keepOnly(["hl"]))

  private static let instagramNames = rule(
    "test.instagram", .host(exact: [], suffix: ["instagram.com"]), .names(["igsh"]))

  private func clean(_ input: String, with rules: [Rule]) throws -> CleanResult {
    RuleCompiler.compile(rules).clean(try #require(URL(string: input)))
  }

  @Test(arguments: [
    ("/reel", true),
    ("/reel/", true),
    ("/reel/X/", true),
    ("/reels/X/", false),
    ("/REEL/X/", false),
    ("/x/reel/", false),
  ])
  func prefixMatchesOnSegmentBoundary(path: String, matches: Bool) throws {
    let result = try clean(
      "https://www.example.com\(path)?tag=1", with: [Self.tagRule(prefixes: ["/reel"])])
    #expect(result.wasModified == matches)
  }

  @Test(arguments: [
    ("/p/", true),
    ("/p/X", true),
    ("/p", false),
    ("/px/", false),
  ])
  func trailingSlashPrefixMatchesByStartsWith(path: String, matches: Bool) throws {
    let result = try clean(
      "https://example.com\(path)?tag=1", with: [Self.tagRule(prefixes: ["/p/"])])
    #expect(result.wasModified == matches)
  }

  @Test func emptyPathMatchesAsRoot() throws {
    let result = try clean("https://example.com?tag=1&q=2", with: [Self.tagRule(prefixes: ["/"])])
    #expect(result.cleanedURL.absoluteString == "https://example.com?q=2")
  }

  @Test func percentEncodedPathComparedRaw() throws {
    let input = "https://example.com/caf%C3%A9/x?tag=1"
    #expect(try clean(input, with: [Self.tagRule(prefixes: ["/caf%C3%A9"])]).wasModified)
    #expect(try clean(input, with: [Self.tagRule(prefixes: ["/café"])]).wasModified == false)

    let escaped = "https://example.com/r%65el/x?tag=1"
    #expect(try clean(escaped, with: [Self.tagRule(prefixes: ["/reel"])]).wasModified == false)
  }

  @Test func queryAndFragmentAreNotPath() throws {
    let rules = [Self.tagRule(prefixes: ["/reel"])]
    let decoy = try clean("https://example.com/other?next=/reel/x&tag=1#/reel/", with: rules)
    #expect(decoy.wasModified == false)

    let real = try clean("https://example.com/reel/x?tag=1&q=2#/other", with: rules)
    #expect(real.cleanedURL.absoluteString == "https://example.com/reel/x?q=2#/other")
  }

  @Test func composesWithHostRuleOnSharePath() throws {
    let result = try clean(
      "https://www.instagram.com/reel/ABC/?igsh=1&token=2&hl=en",
      with: [Self.instagramShare, Self.instagramNames])
    #expect(result.cleanedURL.absoluteString == "https://www.instagram.com/reel/ABC/?hl=en")
    #expect(result.removedParameterNames == ["igsh", "token"])
  }

  @Test func onlyHostRuleAppliesOffSharePath() throws {
    let result = try clean(
      "https://www.instagram.com/accounts/password/reset/confirm/?igsh=1&token=2&hl=en",
      with: [Self.instagramShare, Self.instagramNames])
    #expect(
      result.cleanedURL.absoluteString
        == "https://www.instagram.com/accounts/password/reset/confirm/?token=2&hl=en")
    #expect(result.removedParameterNames == ["igsh"])
  }

  @Test func exactHostDoesNotCoverSubdomain() throws {
    let result = try clean(
      "https://l.instagram.com/reel/ABC/?igsh=1&token=2",
      with: [Self.instagramShare, Self.instagramNames])
    #expect(result.cleanedURL.absoluteString == "https://l.instagram.com/reel/ABC/?token=2")
  }

  @Test func keepOnlyPriorityDecidesBetweenHostPathAndHost() throws {
    let input = "https://www.instagram.com/reel/ABC/?hl=en&q=x"
    let hostKeepsQ = Self.rule(
      "test.host", .host(exact: ["www.instagram.com"], suffix: []), .keepOnly(["q"]))
    func pathKeepsHL(priority: Int) -> Rule {
      Self.rule(
        "test.path", .hostPath(exact: ["www.instagram.com"], suffix: [], pathPrefixes: ["/reel"]),
        .keepOnly(["hl"]), priority: priority)
    }

    let pathWins = try clean(input, with: [hostKeepsQ, pathKeepsHL(priority: 50)])
    #expect(pathWins.cleanedURL.absoluteString == "https://www.instagram.com/reel/ABC/?hl=en")

    let hostWins = try clean(input, with: [pathKeepsHL(priority: 150), hostKeepsQ])
    #expect(hostWins.cleanedURL.absoluteString == "https://www.instagram.com/reel/ABC/?q=x")
  }
}
