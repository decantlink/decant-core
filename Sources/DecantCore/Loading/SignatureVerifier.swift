import Foundation

/// Verifies a detached signature over the exact bytes of a rule bundle.
///
/// Pure ``DecantCore`` owns the trust *policy* (verify-then-parse, anti-rollback) but not the crypto
/// *primitive*: the concrete Ed25519 implementation lives in the `DecantCoreFoundation` adapter and
/// is injected here, so the engine never imports CryptoKit and stays portable. The public key is
/// embedded inside the verifier implementation (supplied by the app), never in core.
public protocol SignatureVerifier: Sendable {
  /// Whether `signature` is a valid signature over `message`.
  /// - Parameters:
  ///   - signature: The detached signature bytes.
  ///   - message: The exact bytes that were signed (the served bundle bytes).
  /// - Returns: `true` iff the signature verifies against the embedded public key.
  func verify(_ signature: Data, of message: Data) -> Bool
}
