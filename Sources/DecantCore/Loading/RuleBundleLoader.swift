import Foundation

/// Loads a rule bundle from bytes through the single trusted path used for both the app-bundled
/// seed and any CDN-fetched update (`SCHEMA.md` §5): **verify the signature over the exact bytes,
/// then enforce anti-rollback, then parse.** Core owns verify+decode; the app owns fetch/cache/schedule.
public struct RuleBundleLoader {
  /// The maximum `schemaVersion` this engine understands.
  public static let supportedSchemaVersion = 1

  /// `RuleDiagnostic.ruleID` sentinel for findings about the bundle as a whole, not a single rule.
  public static let bundleDiagnosticID = "<bundle>"

  private let verifier: SignatureVerifier

  /// Creates a loader.
  /// - Parameter verifier: The injected signature verifier (its public key lives inside it).
  public init(verifier: SignatureVerifier) {
    self.verifier = verifier
  }

  /// Verifies, decodes, and returns a bundle.
  ///
  /// Policy order: verify the signature over `bundleBytes` (reject if invalid) → decode the bytes
  /// (the only re-read of the bytes; never re-serialized before verifying) → reject a non-advancing
  /// `generation` → return. The same path serves the bundled seed and a CDN update; there is no
  /// "trusted because local".
  ///
  /// A `schemaVersion` newer than ``supportedSchemaVersion`` does **not** fail the load (`SCHEMA.md`
  /// §2): because rule meanings are never repurposed, the rules this engine *does* understand are
  /// loaded best-effort and a ``RuleDiagnostic/Severity/warning`` is appended (keyed by
  /// ``bundleDiagnosticID``) for the consumer to surface (e.g. via `reportIssue` / a log).
  ///
  /// - Parameters:
  ///   - bundleBytes: The exact served bytes of `rules.bundle.json`.
  ///   - signature: The detached Ed25519 signature over those bytes.
  ///   - cachedGeneration: The `generation` of the currently-cached bundle, or `nil` if none.
  /// - Returns: The decoded ``RuleBundle`` (its ``RuleBundle/decodeDiagnostics`` lists any rules
  ///   dropped for being un-understood — those never fail the load).
  /// - Throws: ``LoadError`` on signature failure, malformed JSON, unsupported schema, or rollback.
  public func load(bundleBytes: Data, signature: Data, cachedGeneration: Int?) throws -> RuleBundle
  {
    guard verifier.verify(signature, of: bundleBytes) else {
      throw LoadError.badSignature
    }

    let bundle: RuleBundle
    do {
      bundle = try JSONDecoder().decode(RuleBundle.self, from: bundleBytes)
    } catch {
      throw LoadError.malformedJSON
    }

    if let cachedGeneration, bundle.generation <= cachedGeneration {
      throw LoadError.rollback(generation: bundle.generation, cached: cachedGeneration)
    }

    var warnings: [RuleDiagnostic] = []
    if bundle.schemaVersion > Self.supportedSchemaVersion {
      warnings.append(
        RuleDiagnostic(
          ruleID: Self.bundleDiagnosticID,
          severity: .warning,
          message: """
            bundle schemaVersion \(bundle.schemaVersion) is newer than supported \
            \(Self.supportedSchemaVersion); loaded \(bundle.rules.count) understood rule(s) \
            best-effort — update the app for full coverage
            """
        )
      )
    }
    return bundle.appendingDiagnostics(warnings)
  }

  /// Why a load failed.
  public enum LoadError: Error, Equatable {
    /// The signature did not verify against the embedded public key.
    case badSignature
    /// The bundle's `generation` did not advance past the cached one (anti-rollback, §5.2).
    case rollback(generation: Int, cached: Int)
    /// The bytes were not a well-formed bundle envelope.
    case malformedJSON
    /// Reserved: a future *fundamental* data-model change (a major envelope break) that the version
    /// field flags and that cannot be loaded best-effort. **Not thrown today** — a newer
    /// `schemaVersion` whose envelope still parses degrades gracefully with a warning instead, and a
    /// genuinely unparseable envelope surfaces as ``malformedJSON``.
    case unsupportedSchemaVersion(Int)
  }
}
