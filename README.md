# IBM Verify DC Wallet SDK for iOS

IBM's distribution of the [EUDI Wallet Kit library for iOS](https://github.com/eu-digital-identity-wallet/eudi-lib-ios-wallet-kit).

This fork gives IBM control over packaging (pinned transitive dependency versions),
documentation, and distribution stability via semver tags. It carries the minimal possible
code delta over upstream — patches are upstreamed as soon as practical and dropped from this
fork once merged.

---

## Requirements

- iOS 16.0+
- Swift 6.0+
- Xcode 16.0+

---

## SPM Integration

**Xcode project:** File → Add Package Dependencies → enter the URL below and set the version
rule to `Up to Next Major Version` from `1.0.0`.

```
https://github.com/ibm-verify/verify-dc-wallet-sdk-ios.git
```

**Package.swift:**

```swift
// In Package.swift dependencies:
.package(url: "https://github.com/ibm-verify/verify-dc-wallet-sdk-ios.git", from: "1.0.0")

// In your target dependencies:
.product(name: "EudiWalletKit", package: "verify-dc-wallet-sdk-ios")
```

---

## Compatibility

This SDK is the wallet-side (holder) counterpart to IBM's server-side Digital Credentials
products. It is designed to work with:

| Server product | Version |
|---|---|
| [IBM Verify Identity Access Digital Credentials](https://www.ibm.com/docs/en/viadc) (self-hosted) | 26.12 |
| [IBM Verify Digital Credentials](https://www.ibm.com/products/verify/digital-credentials) (SaaS) | 26.12 |

The SDK implements [OpenID for Verifiable Credential Issuance 1.0](https://openid.net/specs/openid-4-verifiable-credential-issuance-1_0.html)
(OID4VCI) and [OpenID for Verifiable Presentations 1.0](https://openid.net/specs/openid-4-verifiable-presentations-1_0-final.html)
(OID4VP) — both Final specifications from the OpenID Foundation's Digital Credentials Protocols
working group. Any issuer or verifier that conforms to these specifications at the dependency
versions pinned in the current `Package.resolved` should be interoperable, but compatibility
is validated and supported only against the IBM server products listed above.

---

## Upstream Version Mapping

| IBM Fork Version | Upstream `eudi-lib-ios-wallet-kit` | Upstream SHA | IBM Patches | Date |
|---|---|---|---|---|
| `v1.0.0` | `v0.35.2` | `181a53cb` | [Fix log entries overwriting each other](#v100--fix-log-entries-overwriting-each-other) | 2026-08-19 |
| `v1.1.0` | `v0.54.8` | `54858f3f` | [Restore stateless VCI auto-config](#v110--restore-stateless-autoregisterviciconfiguration-when-registry-is-empty) · [Honour defaultPolicy .warning for reader chains](#v110--honour-trustconfigurationdefaultpolicy-warning-for-x509-reader-chains) · [Skip WRPRC extraction under .warning policy](#v110--skip-wrprc-extraction-when-wrprcvptrustpolicy-is-warning) · [CI workflow housekeeping](#v110--retain-upstream-ci-workflow-housekeeping) | 2026-10-15 |

---

## IBM Patches

### `v1.0.0` — Fix log entries overwriting each other

**Commit:** `e33c6ab7`  
**File:** `Sources/EudiWalletKit/Services/FileLogging.swift`

Upstream `v0.35.2` initialises the file log handler with `FileHandle(forWritingTo:)` followed by
`seekToEndOfFile()`. On some platforms this overwrites existing file content instead of appending.
The IBM patch replaces this with a POSIX `open(path, O_WRONLY | O_CREAT | O_APPEND)` call so that
log entries are always appended correctly.

An upstream PR will be raised to incorporate this fix. Once merged upstream this patch will be
dropped from the next IBM fork release.

---

### `v1.1.0` — Restore stateless `autoRegisterVciConfiguration` when registry is empty

**Commit:** `9140abe0`  
**File:** `Sources/EudiWalletKit/EudiWallet.swift` (+4, −1)

Upstream `v0.54.8` changed the empty-registry branch of `autoRegisterVciConfiguration` to
throw `missingVciConfiguration`. This broke any consuming app that passes a fully-specified
`OpenId4VciConfiguration` per call (e.g. built from the scanned offer URL at runtime) without
pre-registering a VCI service at startup. Every credential offer immediately failed.

The IBM patch restores the pre-v0.54.8 stateless behaviour: when no fallback service is found
in the registry, a default `OpenId4VciConfiguration` is constructed from the issuer URL rather
than throwing. No pre-registration is required in the calling app.

```swift
// Before (v0.54.8 — throws):
throw WalletError(description: "VCI configuration not provided …", code: .missingVciConfiguration)

// After (IBM patch — restores stateless behaviour):
config = OpenId4VciConfiguration(credentialIssuerURL: urlString)
```

> **Watch point:** upstream introduced this throw deliberately. If a future upstream release
> re-introduces it, the IBM patch will conflict on the next sync. Monitor
> `autoRegisterVciConfiguration` in upstream diffs.

---

### `v1.1.0` — Honour `TrustConfiguration.defaultPolicy .warning` for x509 reader chains

**Commit:** `18595ff6`  
**Files:** `Sources/EudiWalletKit/Services/OpenId4VpService.swift` (+15, −4) · `Tests/.../OpenId4VpAuthenticationTests.swift` (+32, −2)

Upstream commit `dcaca10c` (included in v0.54.8) added a strict `guard readerAuthValidated`
gate in `OpenId4VpService` that fires before a VP response is sent. This gate blocks all
OpenID4VP presentations when the reader's X.509 chain fails trust validation — even when the
app has configured `TrustConfiguration(defaultPolicy: .warning)`. The result was every
QR-scanned verification failing with _"Required reader certificate authentication was not
established"_, regardless of the configured policy.

The IBM patch adds a second Boolean flag `readerTrustAcceptedByPolicy` to `OpenId4VpService`.
The `chainVerifier` closure sets this flag (and returns `true`) when trust validation fails but
`defaultPolicy == .warning`, logging a warning. The reader-auth guard is widened to
`readerAuthValidated || readerTrustAcceptedByPolicy`. `readerAuthValidated` stays `false` so
the UI correctly reports the reader as untrusted — only the hard block is lifted. The JAR
signature and leaf-certificate match checks remain fully enforced.

```swift
// chainVerifier — new block (IBM patch):
if !isValid && self.trustConfig.defaultPolicy == .warning {
    logger.warning("Reader cert chain not trusted (defaultPolicy=.warning, proceeding): …")
    self.readerTrustAcceptedByPolicy = true
    return true
}

// Reader-auth guard — widened (IBM patch):
guard readerAuthValidated || readerTrustAcceptedByPolicy, let leaf = certificateChain?.first, …
```

> **Production note:** `defaultPolicy: .warning` is a development convenience. For production
> deployments set `defaultPolicy: .enforce` so untrusted reader chains are hard-rejected.

---

### `v1.1.0` — Skip WRPRC extraction when `wrprcVpTrustPolicy` is `.warning`

**Commit:** `4a6a57b0`  
**File:** `Sources/EudiWalletKit/Services/OpenId4VpService.swift` (+5, −1)

Upstream `v0.54.8` introduced WRPRC (Wallet Relying Party Registration Certificate) validation
via `registrationCertificatePolicy`. When `wrprcVpTrustPolicy == .warning` and the verifier
gateway does not include `verifier_info` in the JAR, the upstream `openid4vp-swift` library
throws a hard `ValidationError` before the IBM trust-policy check can run, blocking all
verification against gateways that pre-date the WRPRC feature (e.g. DMV gamma).

The IBM patch gates `registrationCertificatePolicy` on
`trustConfig.wrprcVpTrustPolicy == .enforce`, so WRPRC extraction is skipped entirely under
`.warning`, restoring the pre-v0.54.8 behaviour where the feature did not exist.

```swift
// Before (v0.54.8 — WRPRC extraction always attempted when validateRegistrationCertificate is true):
registrationCertificatePolicy: openID4VpConfig.validateRegistrationCertificate
    ? .default(validator: wrpRegistrationValidator) : nil

// After (IBM patch — skipped when wrprcVpTrustPolicy is .warning):
registrationCertificatePolicy: openID4VpConfig.validateRegistrationCertificate
    && trustConfig.wrprcVpTrustPolicy == .enforce
    ? .default(validator: wrpRegistrationValidator) : nil
```

---

### `v1.1.0` — Retain upstream CI workflow (housekeeping)

**Commit:** `033dc444`  
**File:** `.github/workflows/swift.yml` (+7, −5)

Reverts an accidental edit to the CI workflow introduced during the upstream v0.54.8 merge.
The upstream workflow uses `swift build` / `swift test` directly; the accidental edit had
replaced it with Fastlane. No functional change to the SDK. A comment has been added
explaining the revert is intentional pending a review of PAT workflow scope for the IBM fork.

---

## IBM Patch Policy

- **Upstream first.** Any fix or feature that is generally useful is raised as an upstream PR
  at the same time it is carried here.
- **Patches are temporary.** A patch is dropped from this fork as soon as it is merged upstream
  and included in a new upstream release that this fork syncs to.
- **Breaking upstream changes.** If a new upstream release contains breaking API changes that
  require app changes, the IBM fork version is bumped to the next `MAJOR`. The previous IBM
  version tag remains available for pinning until the app migration is complete.

---

## How to Sync Upstream

1. Assess the upstream release notes — identify breaking changes and decide MAJOR/MINOR/PATCH bump
2. Create a `sync/vX.Y.Z` branch from `main`
3. `git merge upstream/vX.Y.Z` — resolve conflicts only in `Package.swift` and `README.md`
4. Re-apply IBM patches that have not yet been merged upstream; drop those that have
5. Update `Package.swift` dependency versions to match upstream's resolved versions
6. Update the **Upstream Version Mapping** table above
7. Open a PR into `main`, merge, tag, and create a GitHub Release
8. Update the consuming app to the new version

---

## Versioning Scheme

This fork uses independent semver (`vMAJOR.MINOR.PATCH`) starting at `v1.0.0`.

| Segment | When to increment |
|---|---|
| `MAJOR` | Upstream breaking API changes that require changes in the consuming app |
| `MINOR` | Sync to a new upstream release with no breaking changes to IBM consumers |
| `PATCH` | IBM-only hotfix between upstream syncs |

---

## License

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE) for the full text.
