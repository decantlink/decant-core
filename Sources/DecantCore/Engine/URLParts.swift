import Foundation

/// A URL split into the three byte-spans that surgical splicing cares about, **without** going
/// through `URLComponents` (which re-percent-encodes, turns `+`↔space, and can reorder or drop).
///
/// The split is purely lexical on the absolute string:
/// - `fragment` is everything from the first `#` (inclusive) to the end, untouched.
/// - `prefix` is everything up to the first `?` (the `?` itself excluded).
/// - `rawQuery` is the bytes between that `?` and the fragment; `nil` if there is no `?`.
///
/// Reconstruction keeps `prefix` and `fragment` byte-verbatim and only re-joins the kept query
/// tokens, so "copy-perfect" fidelity (`SCHEMA.md` §7) reduces to never touching the remainder.
struct URLParts {
  let prefix: Substring
  let rawQuery: Substring?
  let fragment: Substring

  /// Splits an absolute URL string. A `?` appearing inside the fragment is part of the fragment.
  init(_ absolute: String) {
    let beforeFragment: Substring
    if let hash = absolute.firstIndex(of: "#") {
      fragment = absolute[hash...]
      beforeFragment = absolute[..<hash]
    } else {
      fragment = absolute[absolute.endIndex...]
      beforeFragment = absolute[...]
    }

    if let question = beforeFragment.firstIndex(of: "?") {
      prefix = beforeFragment[..<question]
      rawQuery = beforeFragment[beforeFragment.index(after: question)...]
    } else {
      prefix = beforeFragment
      rawQuery = nil
    }
  }

  /// Rebuilds an absolute URL string from the kept query tokens.
  /// - Parameter keptTokens: The raw, byte-verbatim query tokens to retain, in original order.
  /// - Returns: `prefix + "?" + tokens-joined-by-& + fragment`, or `prefix + fragment` when empty
  ///   (the `?` is dropped when nothing remains, per §7).
  func reassembled(keptTokens: [Substring]) -> String {
    if keptTokens.isEmpty {
      return String(prefix) + String(fragment)
    }
    return String(prefix) + "?" + keptTokens.joined(separator: "&") + String(fragment)
  }
}
