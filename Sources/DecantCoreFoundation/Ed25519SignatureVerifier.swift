import CryptoKit
import DecantCore
import Foundation

/// The Apple-platform ``SignatureVerifier`` adapter: Ed25519 verification via CryptoKit.
///
/// This is the only place CryptoKit is imported. The public key is supplied by the **app** as raw
/// bytes (pinned in the app binary, `SCHEMA.md` §5.1) and held here, keeping the crypto primitive in
/// the adapter and the trust policy in pure ``DecantCore``.
public struct Ed25519SignatureVerifier: SignatureVerifier {
  private let publicKey: Curve25519.Signing.PublicKey

  /// Creates a verifier from a 32-byte raw Ed25519 public key.
  /// - Parameter rawPublicKey: The raw public-key bytes pinned in the app.
  /// - Throws: If `rawPublicKey` is not a valid Curve25519 signing public key.
  public init(rawPublicKey: Data) throws {
    publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: rawPublicKey)
  }

  public func verify(_ signature: Data, of message: Data) -> Bool {
    publicKey.isValidSignature(signature, for: message)
  }
}
