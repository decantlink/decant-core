import Foundation

/// A lazily-compiled regular expression used by `regex` selectors and `hostRegex` matchers.
///
/// Most selectors are `names`/`prefix` (no regex), and host regexes are rare. To honor the
/// cold-start budget — *never compile all regexes at init* — the pattern is held as a string and
/// the `NSRegularExpression` is built on first use and cached. The cache is guarded by a lock so the
/// engine stays `Sendable` and `clean` can remain non-mutating.
final class CompiledRegex: @unchecked Sendable {
  private let pattern: String
  private let lock = NSLock()
  /// `nil` = not yet attempted; `.some(nil)` = compilation failed; `.some(re)` = compiled.
  private var cached: NSRegularExpression??

  init(_ pattern: String) {
    self.pattern = pattern
  }

  /// Whether `string` matches the pattern. A pattern that fails to compile matches nothing.
  func matches(_ string: String) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    if cached == nil {
      cached = .some(try? NSRegularExpression(pattern: pattern))
    }
    guard let regex = cached ?? nil else { return false }
    let range = NSRange(string.startIndex..., in: string)
    return regex.firstMatch(in: string, options: [], range: range) != nil
  }
}
