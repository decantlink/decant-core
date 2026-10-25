import CryptoKit
import DecantCoreFoundation
import Foundation
import Testing

@testable import DecantCore

/// Gate 4: RuleBundleLoader + Ed25519 verifier — tampered bytes reject, rollback rejects, a valid
/// signed bundle loads. Uses a throwaway keypair generated per run.
struct RuleBundleLoaderTests {
  private func seedBytes() throws -> Data {
    let url = try #require(Bundle.module.url(forResource: "rules.bundle", withExtension: "json"))
    return try Data(contentsOf: url)
  }

  private func makeLoader(publicKey: Curve25519.Signing.PublicKey) throws -> RuleBundleLoader {
    let verifier = try Ed25519SignatureVerifier(rawPublicKey: publicKey.rawRepresentation)
    return RuleBundleLoader(verifier: verifier)
  }

  @Test func validSignedBundleLoads() throws {
    let key = Curve25519.Signing.PrivateKey()
    let bytes = try seedBytes()
    let signature = try key.signature(for: bytes)
    let loader = try makeLoader(publicKey: key.publicKey)

    let bundle = try loader.load(bundleBytes: bytes, signature: signature, cachedGeneration: nil)
    #expect(bundle.rules.count == 9)
    #expect(bundle.generation == 1)
  }

  @Test func tamperedBytesRejected() throws {
    let key = Curve25519.Signing.PrivateKey()
    let bytes = try seedBytes()
    let signature = try key.signature(for: bytes)
    let loader = try makeLoader(publicKey: key.publicKey)

    var tampered = bytes
    tampered.append(0x20)  // trailing space invalidates the signature over the original bytes
    #expect(throws: RuleBundleLoader.LoadError.badSignature) {
      try loader.load(bundleBytes: tampered, signature: signature, cachedGeneration: nil)
    }
  }

  @Test func wrongKeyRejected() throws {
    let signingKey = Curve25519.Signing.PrivateKey()
    let bytes = try seedBytes()
    let signature = try signingKey.signature(for: bytes)
    // Verify against an unrelated key.
    let loader = try makeLoader(publicKey: Curve25519.Signing.PrivateKey().publicKey)

    #expect(throws: RuleBundleLoader.LoadError.badSignature) {
      try loader.load(bundleBytes: bytes, signature: signature, cachedGeneration: nil)
    }
  }

  @Test func nonAdvancingGenerationRejected() throws {
    let key = Curve25519.Signing.PrivateKey()
    let bytes = try seedBytes()  // generation == 1
    let signature = try key.signature(for: bytes)
    let loader = try makeLoader(publicKey: key.publicKey)

    #expect(throws: RuleBundleLoader.LoadError.rollback(generation: 1, cached: 1)) {
      try loader.load(bundleBytes: bytes, signature: signature, cachedGeneration: 1)
    }
    #expect(throws: RuleBundleLoader.LoadError.rollback(generation: 1, cached: 5)) {
      try loader.load(bundleBytes: bytes, signature: signature, cachedGeneration: 5)
    }
  }

  @Test func advancingGenerationAccepted() throws {
    let key = Curve25519.Signing.PrivateKey()
    let bytes = try seedBytes()  // generation == 1
    let signature = try key.signature(for: bytes)
    let loader = try makeLoader(publicKey: key.publicKey)

    let bundle = try loader.load(bundleBytes: bytes, signature: signature, cachedGeneration: 0)
    #expect(bundle.generation == 1)
  }

  @Test func newerSchemaVersionDegradesGracefullyWithWarning() throws {
    // A future bundle whose rules still parse under v1 grammar: load best-effort, warn, don't throw.
    let json = """
      { "schemaVersion": 2, "generation": 3, "generatedAt": "2026-06-26T00:00:00Z", "rules": [
        { "id": "tracking.utm", "name": "UTM", "matcher": { "type": "any" },
          "actions": [ { "type": "removeParameters", "select": { "prefix": "utm_" } } ], "source": "builtIn" }
      ] }
      """
    let key = Curve25519.Signing.PrivateKey()
    let bytes = Data(json.utf8)
    let signature = try key.signature(for: bytes)
    let loader = try makeLoader(publicKey: key.publicKey)

    let bundle = try loader.load(bundleBytes: bytes, signature: signature, cachedGeneration: nil)
    #expect(bundle.rules.map(\.id) == ["tracking.utm"])
    let warnings = bundle.decodeDiagnostics.filter { $0.severity == .warning }
    #expect(warnings.count == 1)
    #expect(warnings.first?.ruleID == RuleBundleLoader.bundleDiagnosticID)
  }

  @Test func malformedJSONRejected() throws {
    let key = Curve25519.Signing.PrivateKey()
    let bytes = Data("{ not json".utf8)
    let signature = try key.signature(for: bytes)
    let loader = try makeLoader(publicKey: key.publicKey)

    #expect(throws: RuleBundleLoader.LoadError.malformedJSON) {
      try loader.load(bundleBytes: bytes, signature: signature, cachedGeneration: nil)
    }
  }
}
