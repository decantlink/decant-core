import Foundation

/// A URL's query split into byte-verbatim tokens, exactly as ``CompiledRuleSet/clean(_:)`` splits
/// it, and rebuilt with any chosen tokens left out.
///
/// The query is split on `&` only; `;` is not a separator (WHATWG). Empty tokens (from `&&` or a
/// trailing `&`) are not parameters and are always kept verbatim when the URL is rebuilt.
public struct QueryParameters: Sendable, Equatable {
  /// One non-empty query token.
  public struct Parameter: Sendable, Hashable {
    /// The parameter's position in ``QueryParameters/parameters``.
    public let index: Int
    /// The name as it appears on the wire, spelled as in ``CleanResult/removedParameterNames``.
    public let onWireName: String
    /// The percent-decoded name rules match against; ``onWireName`` when it does not decode.
    public let decodedName: String
    /// The full token, verbatim.
    public let raw: String
  }

  /// The non-empty tokens, in original order.
  public let parameters: [Parameter]

  private let url: URL
  private let parts: URLParts
  private let tokens: [Substring]

  /// Splits the query of `url`.
  public init(_ url: URL) {
    let parts = URLParts(url.absoluteString)
    let tokens = parts.rawQuery?.split(separator: "&", omittingEmptySubsequences: false) ?? []
    var parameters: [Parameter] = []
    for token in tokens where !token.isEmpty {
      let onWireName = String(token.firstIndex(of: "=").map { token[..<$0] } ?? token)
      parameters.append(
        Parameter(
          index: parameters.count, onWireName: onWireName,
          decodedName: onWireName.removingPercentEncoding ?? onWireName, raw: String(token)))
    }
    self.url = url
    self.parts = parts
    self.tokens = tokens
    self.parameters = parameters
  }

  /// The original URL with the given parameters left out; everything else stays byte-identical.
  ///
  /// Indices that name no parameter are ignored. When nothing is left out the original URL is
  /// returned. The `?` is dropped only when no token, empty or not, remains.
  /// - Returns: The rebuilt URL, or `nil` if the spliced string no longer parses as a URL.
  public func url(omitting indices: Set<Int>) -> URL? {
    guard indices.contains(where: parameters.indices.contains) else { return url }
    var kept: [Substring] = []
    var index = 0
    for token in tokens {
      if token.isEmpty {
        kept.append(token)
        continue
      }
      if !indices.contains(index) { kept.append(token) }
      index += 1
    }
    return URL(string: parts.reassembled(keptTokens: kept))
  }
}
