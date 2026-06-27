# DecantCore — Engine Design

Why the engine is shaped the way it is. The **data format** is specified by `SCHEMA.md` in the
sibling repo `decantlink/decant-rules` (the cross-repo, cross-language contract); this document
covers the **engine** that consumes it. Where the two overlap, `SCHEMA.md` is the
source of truth for the format and this file explains the runtime rationale — it does not
re-specify the schema.

> Status: v1 (MVP) — query-parameter **removal** only ("Phase 0 / clean"). Rewrite and routing
> actions are reserved in the contract but not built. The model is shaped so they slot in
> additively (see [Deferred](#9-deferred-phase-1--2)).

---

## 1. What it is

A deterministic, on-device URL cleaner. Given a `URL`, it removes tracking query parameters and
returns the cleaned URL plus an accounting of what was removed:

```swift
public protocol RuleEngine: Sendable {
  func clean(_ url: URL) -> CleanResult
}
```

Two invariants hold for every implementation:

- **Deterministic + side-effect-free.** Same URL → same `CleanResult`, always.
- **The URL never leaves the device.** No network, no logging of URLs, no shared mutable state.

`RuleEngine` is the stable seam the app depends on (wrapped as a TCA dependency). The concrete
engine is `CompiledRuleSet`, which *is* a `RuleEngine` — there is no separate object to wire.

---

## 2. Three-layer rule model

The same logical rule exists in three forms, each optimized for a different job. This split is the
spine of the whole system; `SCHEMA.md §1` defines the format of each.

| Layer | Form | Owned by | Optimized for |
|---|---|---|---|
| **Authoring** | many small JSON files, per category | `decant-rules/rules/*.json` | human review — clean diffs, blame, PRs |
| **Delivery** | one signed bundle | `decant-rules/dist/rules.bundle.json` (+ `.sig`) | integrity + one fetch; CI-compiled |
| **Runtime** | in-memory compiled indices | `decant-core` only | O(params) matching; never serialized |

The runtime form never round-trips back to JSON. The pipeline is one-way:
**verify bytes → parse → compile to indices.** Re-serializing rules at runtime is both wasted work
and an attack surface (JSON is not byte-stable), so the engine never does it.

### Two products, one boundary

`DecantCore` is **Foundation-only and crypto-free** (`URL`/`Data`/`Date`, no CryptoKit, no UIKit).
The Ed25519 primitive lives in a separate `DecantCoreFoundation` adapter and is injected through the
`SignatureVerifier` protocol. The core owns the trust *policy* (verify-then-parse, anti-rollback);
the adapter owns the crypto *primitive*. This keeps the engine portable (a future Kotlin/JS port
honors the same contract) and keeps the platform surface out of the deterministic core.

---

## 3. Loading pipeline — one trusted path

`RuleBundleLoader.load(bundleBytes:signature:cachedGeneration:)` is the single entry for *both* the
app-bundled seed and any CDN-fetched update. There is no "trusted because local": the seed bundle is
itself a signed bundle through the same path. Policy order (`SCHEMA.md §5`):

1. **Verify** the detached Ed25519 signature over the **exact served bytes**. Invalid → `badSignature`.
   Never canonicalize or re-serialize before verifying.
2. **Parse** those same bytes (the only re-read). Malformed → `malformedJSON`.
3. **Anti-rollback:** reject a bundle whose `generation` ≤ the cached one, even if validly signed —
   stops a CDN/MITM replaying an older signed bundle to re-expose a removed bad rule. → `rollback`.

The public key is pinned inside the verifier (supplied by the app), never in core. The private key
is a CI secret. Signing is **integrity, not secrecy** — rules are public (MIT). In removal-only v1 a
forged bundle's worst case is over- or under-removal (annoying, not catastrophic); the single verify
path is established now, before routing actions raise the blast radius.

Core owns verify + decode; the app owns fetch, cache, and schedule.

---

## 4. Validation — decode-time vs semantic

Validity is enforced in two places, by design:

- **Structural constraints are enforced at decode time** because they are not representable in the
  Swift value model. An unknown `matcher`/`action` `type` fails decoding of the *enclosing rule*
  (so the bundle drops it whole rather than partial-applying a half-understood rule — a half-applied
  rule is a broken URL). A `Selector` is an enum, so "exactly one of `names`/`prefix`/`regex`/
  `keepOnly`" is a type guarantee, not a runtime check.
- **`RuleValidator` covers the semantic constraints a well-typed value can still violate:**
  unanchored `hostRegex` (`amazon.*` would match `amazon.com.phishing.ru` — must be `^…$`),
  uncompilable `hostRegex`, a degenerate `host` with neither `exact` nor `suffix` (matches nothing).
  These reject the rule with a `skippedRule` diagnostic. `removeAllParameters` next to a
  `removeParameters` earns a `warning` but is kept (the latter is subsumed).

Validation never throws on rule-level problems — it partitions input into `(accepted, diagnostics)`.
A bad rule is dropped and reported; it never sinks the bundle.

---

## 5. Compilation — build the indices once

`RuleCompiler.compile` runs **once** (the share extension builds the engine and holds it); it is
never repeated per `clean`. Each enabled rule is folded by its matcher kind into one of three runtime
structures:

- `.any` rules → folded into a single **global** `ParamRemovalSet` (computed once).
- `.host(exact:suffix:)` rules → registered in `byExact` / `bySuffix` maps keyed by each host literal.
- `.hostRegex` rules → a small **linear** list of `(compiled regex, rule)`.

Folding a rule once at compile time precomputes its removal criteria and keeps its compiled regex
instances stable, so their lazy caches persist across cleans.

---

## 6. Matcher strategy — O(params), not O(rules)

Matching a URL must not scan every rule. Given a host like `www.amazon.co.uk`, the engine probes its
label-boundary suffixes — `[www.amazon.co.uk, amazon.co.uk, co.uk, uk]` — plus an exact probe against
the host maps, then tests the (small, audited) regex list. It never walks the whole rule set.

Design choices and the reasons behind them:

- **Author-declared host scoping, no Public Suffix List.** A cleaner sees **one URL in isolation** —
  there is no page context, so no first-party/third-party determination and no PSL. The label-boundary
  rule "`D` matches `H` iff `H == D` or `H` ends with `.D`" is realized by suffix-probing, not a PSL.
- **Multi-ccTLD brands are a data list, not a wildcard.** Amazon is `suffix: ["amazon.com",
  "amazon.es", "amazon.co.uk", …]` — diff-reviewable; a missing TLD is a one-line PR. `hostRegex` is
  the audited escape hatch (anchored only), used sparingly because every regex is an unreviewable
  matcher.
- **Most many-TLD tracking is global anyway.** `gclid`/`utm_*` strip on `{ "type": "any" }`, so
  Google's ~190 ccTLDs never need enumerating. Only brand-specific params are host-scoped.
- **Not a speculative trie.** The spec's early "domain trie / path trie" was dropped: with global
  params folded once and host literals in a dictionary, a trie buys nothing for v1's host-only
  dimension and adds structure to maintain. A per-host path dimension arrives (additively) only when
  rewrite/route actions need it.

---

## 7. Cleaning semantics — copy-perfect splice

For a matched URL the engine merges the global fold with every matching host fold into one
`ParamRemovalSet`, then walks the query tokens once. Clean-phase actions are **commutative and
batched** (union of removals) across all matching rules — with one exception:

- **`keepOnly` does not stack.** It is a complement op, not commutative with other allowlists. The
  **highest-priority** (lowest `priority` number) matching rule's allowlist wins; `names`/`prefix`/
  `regex` removals from all rules still apply on top. Ties are broken by `priority`, folded in at
  compile time.
- **Name comparison is percent-decoded and case-sensitive** (`SCHEMA.md §4`). Removed names are
  reported back in their **original on-wire spelling** (percent-encoded as they appeared).

Output is a **surgical splice on the raw query substring**, never a round-trip through
`URLComponents` (which re-percent-encodes, flips `+`↔space, and can reorder or drop). `URLParts`
splits the absolute string lexically on the first `?` and `#`; `prefix` and `fragment` are kept
**byte-verbatim** and only the kept query tokens are re-joined with `&`. Copy-perfect fidelity
(`SCHEMA.md §7`) thus reduces to *never touching the remainder*. This is the highest bug-density
component and has a dedicated byte-exact fixture corpus (`Tests/.../url-fidelity.json`): leading
param with no `&`, `;` (not a separator), `+`/space, fragments containing `?`, empty values,
valueless params, repeated names, percent-encoded names.

When nothing matches — no query, no applicable removals, or no token actually removed — `clean`
returns `CleanResult.unchanged(url)` with the input URL untouched.

---

## 8. Version-skew — degrade, never crash

`schemaVersion` is a single **integer**, bumped only on a breaking change; the contract evolves
**additive-only** and a field's meaning is never repurposed. An engine declares the max version it
understands (`RuleBundleLoader.supportedSchemaVersion`). Skip granularity (`SCHEMA.md §2`):

| Engine encounters | Behavior |
|---|---|
| Unknown **action** / **matcher** `type` | skip the whole rule (decode-time) |
| Unknown **optional field** value (e.g. `category`) | ignore the field, keep the rule |
| `schemaVersion` > supported | load the understood rules best-effort, append a `warning` diagnostic — **never fail the bundle** |

Rationale: an old client meeting a future routing rule must keep cleaning with the rules it does
understand. The reserved `unsupportedSchemaVersion` error exists for a hypothetical fundamental
envelope break and is **not thrown today** — a newer-but-parseable bundle degrades with a warning,
and a genuinely unparseable envelope surfaces as `malformedJSON`.

---

## 9. Deferred (Phase 1 & 2)

Reserved in the contract, intentionally **not** built in v1:

- **Rewrite** (`rewriteURL`, `expandURL`) and **route** (`redirect`, `openInApp`) actions. The
  eventual phase model is **clean → rewrite → route**: rewrite and route each at most one per rule,
  route terminal.
- **Loop detection** and **redirect-safety** validation — concerns of the route phase only. They do
  not exist in v1 because removal-only cleaning cannot loop or redirect.
- **Path matching** (`path` / `pathPattern`) and **compound** matchers (`allOf`/`anyOf`/`noneOf`) —
  arrive with rewrite/routing; the host index gains a path dimension then, additively.

These are listed so a reader does not mistake their absence for an oversight. The value model,
tagged-union matchers/actions, and the loader's skip-and-warn behavior are all shaped so these land
**without a repaint**.

---

## 10. Pointers

- **Data format (source of truth):** `SCHEMA.md` in `decantlink/decant-rules`.
- **Engine API seam (canonical here):** `RuleEngine.clean(_:) -> CleanResult`.
- **Layout:** `Sources/DecantCore/{Engine,Loading,Models,Validation}` +
  `Sources/DecantCoreFoundation` (Ed25519 adapter). See `README` / `CLAUDE.md` for the file map.
