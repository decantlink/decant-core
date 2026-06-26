# decant-core — Decant rule engine (public, MIT)

Deterministic, on-device URL-cleaning engine. Consumes the signed rule bundle defined by
`decant-rules`; exposes the cleaning API the app depends on. Foundation-only core; no UIKit/
SwiftUI/AppKit. Standalone Swift package — clones build with no extra setup.

## Structure

```
Sources/DecantCore/           pure engine (Foundation only: URL/Data/Date; no CryptoKit)
  Engine/                     RuleEngine, CleanResult, RuleCompiler, CompiledRuleSet, URLParts
  Loading/                    RuleBundleLoader, SignatureVerifier (protocol)
  Models/                     Rule, RuleBundle, Codable, decoding errors
  Validation/                 RuleValidator, RuleDiagnostic
Sources/DecantCoreFoundation/ CryptoKit-backed Ed25519 verifier (kept out of the pure core)
Tests/DecantCoreTests/        model decoding, bundle loader, validator, URL-fidelity
```

## Commands

| Command | Description |
|---|---|
| `swift build` | build both library products |
| `swift test` | run all tests (uses bundled `Resources/rules.bundle.json` + fidelity corpus) |

Products: `DecantCore` (pure) + `DecantCoreFoundation` (Apple crypto adapter). Platforms macOS 13 / iOS 16+.

## Conventions

- `DecantCore` stays **crypto-free and platform-free** — anything needing CryptoKit/Apple SDKs goes in `DecantCoreFoundation`.
- Engine is **deterministic + side-effect-free**: same URL → same `CleanResult`; URLs never leave the device.
- Runtime never re-serializes rules — verify bytes, then parse, then compile to in-memory indices.

## Contracts

- Engine API → **canonical here**: `RuleEngine.clean(_:) -> CleanResult`. (`decant-apple` ships a temporary stub copy of this seam; this repo is the source of truth.)
- Rule data format → **consumed from** `decant-rules/SCHEMA.md` + `schema/*.json`. Don't redefine the schema here; conform the decoder/validator to it.

## Pointers
- Current state: `~/.agents/memories/Decant/SUMMARY.md` · Decisions: vault Bible §12 · Cross-repo map: `decant-meta/AGENTS.md`.

<!-- Update on: public API change, new target/product, changed schema conformance, new test resource. -->
