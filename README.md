# IBM Verify DC Wallet SDK for iOS

IBM's distribution of the [EUDI Wallet Kit library for iOS](https://github.com/eu-digital-identity-wallet/eudi-lib-ios-wallet-kit).

This fork gives IBM control over packaging (pinned transitive dependency versions),
documentation, and distribution stability via semver tags. It carries the minimal possible
code delta over upstream — patches are upstreamed as soon as practical and dropped from this
fork once merged.

---

## Requirements

- iOS 17.0+
- Swift 6.2+
- Xcode 26.0+

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
| `v1.1.0` | `v0.56.1` | `2df9cfba` | [Restore stateless VCI auto-config](#v110--restore-stateless-autoregisterviciconfiguration-when-registry-is-empty) · [Skip WRPRC extraction under .warning policy](#v110--skip-wrprc-extraction-when-wrprcvptrustpolicy-is-warning) · [CI workflow housekeeping](#v110--ci-workflow-housekeeping) | 2026-10-20 |

> **`v1.1.0` history:** `v1.1.0` was first cut against upstream `v0.54.8` (`54858f3f`) and
> re-pointed at upstream `v0.56.1` on 2026-10-20. That change drops the
> `defaultPolicy .warning` reader-chain patch, which upstream now covers with
> `TrustConfiguration.readerTrustPolicy` (see [Dropped patches](#dropped-patches)).

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

Since upstream `v0.36.0` (commit `81a26c83`, a compile fix after an OpenID4VCI library update,
with no changelog entry) the empty-registry branch of `autoRegisterVciConfiguration` throws
`WalletError.missingVciConfiguration`. This breaks any consuming app that passes a
fully-specified `OpenId4VciConfiguration` per call (e.g. built from the scanned offer URL at
runtime) without pre-registering a VCI service at startup: every credential offer fails in
`resolveOfferUrlDocTypes`. IBM `v1.0.0` (based on upstream `v0.35.2`) pre-dates the throw.

The IBM patch keeps the original stateless behaviour: when no fallback service is found in the
registry, a default `OpenId4VciConfiguration` is constructed from the issuer URL rather than
throwing. No pre-registration is required in the calling app.

```swift
// Upstream (throws):
throw WalletError(description: "VCI configuration not provided …", code: .missingVciConfiguration)

// IBM patch (stateless):
config = OpenId4VciConfiguration(credentialIssuerURL: urlString)
```

> **Watch point:** the upstream source has a `Todo: validate … by a trusted list` comment in
> this function, so upstream may restrict unregistered issuers in future. If a future upstream
> release changes `autoRegisterVciConfiguration`, this patch will conflict on the next sync.
> Monitor that function in upstream diffs.

---

### `v1.1.0` — Skip WRPRC extraction when `wrprcVpTrustPolicy` is `.warning`

**Commit:** `4a6a57b0`  
**File:** `Sources/EudiWalletKit/Services/OpenId4VpService.swift` (+5, −1)

Upstream introduced WRPRC (Wallet Relying Party Registration Certificate) validation via
`registrationCertificatePolicy` in `v0.38.0`, with `wrprcVpTrustPolicy` following in `v0.40.2`. When `wrprcVpTrustPolicy == .warning` and the verifier
gateway does not include `verifier_info` in the JAR, the upstream `openid4vp-swift` library
throws a hard `ValidationError` before the IBM trust-policy check can run, blocking all
verification against gateways that do not send `verifier_info` (e.g. DMV gamma).

The IBM patch gates `registrationCertificatePolicy` on
`trustConfig.wrprcVpTrustPolicy == .enforce`, so WRPRC extraction is skipped entirely under
`.warning`, as if the verifier did not use WRPRC.

```swift
// Upstream (WRPRC extraction always attempted when validateRegistrationCertificate is true):
registrationCertificatePolicy: openID4VpConfig.validateRegistrationCertificate
    ? .default(validator: wrpRegistrationValidator) : nil

// IBM patch (skipped when wrprcVpTrustPolicy is .warning):
registrationCertificatePolicy: openID4VpConfig.validateRegistrationCertificate
    && trustConfig.wrprcVpTrustPolicy == .enforce
    ? .default(validator: wrpRegistrationValidator) : nil
```

---

### `v1.1.0` — CI workflow housekeeping

**File:** `.github/workflows/swift.yml`

The IBM fork's CI workflow differs from upstream: it runs `swift build` and `swift test` on
`macos-latest`, whereas upstream runs `fastlane tests` on `macos-15`. It is left as-is during
upstream syncs pending a review of PAT workflow scope for the IBM fork. No functional change to
the SDK.

---

## Dropped patches

| Patch | Dropped in | Reason |
|---|---|---|
| Honour `TrustConfiguration.defaultPolicy .warning` for x509 reader chains (`18595ff6`) | `v1.1.0` (re-point to `v0.56.1`) | Upstream added `TrustConfiguration.readerTrustPolicy` (default `.enforce`). With `.warning`, a validly signed request with an untrusted reader chain proceeds and reports `ReaderAuthenticationStatus.authenticatedWithUntrustedCertificate`. |

**Migration:** `defaultPolicy` no longer controls reader-chain trust. Apps that relied on
`defaultPolicy: .warning` to accept untrusted reader chains must also set
`readerTrustPolicy: .warning`. As with the old patch, this is a development convenience; use
`.enforce` in production.

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
