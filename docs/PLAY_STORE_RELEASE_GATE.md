# RideGo Play Store release gate — source audit

Audit base: feature/payments-from-tested-build at 756da1a. This is a source/configuration review, **not Play Console approval**.

## Verified in repository

| Area | Rider | Partner | Release impact |
| --- | --- | --- | --- |
| Android application ID | `com.ridego.rider` | `com.example.ridego_driver` | **Partner ID requires a deliberate final decision** before first Play Store upload; package identity is hard to change afterward |
| App version | `1.0.0+2` | `1.0.0+2` | Increase versionCode for every subsequent Play Store update |
| Display label | RideGo | RideGo Partner | Confirm final names and branded icons |
| Checked-in release Gradle config | debug signing fallback | debug signing fallback | **Never upload a locally built artifact using these fallback settings** |
| CI test build | workflow injects keystore-based release signing and builds APK + AAB | workflow injects keystore-based release signing and builds APK + AAB | Use only verified CI release artifacts; confirm certificate and Play App Signing enrollment |
| Two-device acceptance | Pending | Pending | Blocking |
| DigiLocker | Coming soon, no approved requester credentials | Coming soon | Do not claim government verification is live |
| Payment | Cash flow has automated tests | Cash confirmation has automated tests | End-to-end device acceptance still required; do not advertise UPI as live |

## Release blockers in priority order

1. **Freeze Android identity**: decide whether to retain `com.example.ridego_driver` or migrate to `com.ridego.partner` **before first Play Console upload**. Changing it after publication creates a different app. Confirm Firebase Android registration, `google-services.json`, Maps key restrictions, signing fingerprints, and deep links for the chosen ID. Do not rename automatically.
2. **Release signing**: verify both CI-built AABs use intended permanent signing certificates, no debug keys, and that Play App Signing/upload-key arrangements are configured. Never expose keystores/passwords in logs or commits. Check signing certificates after downloading artifacts.
3. **Production policy**: establish privacy policy URL, account deletion flow and public deletion URL, support contact, data safety declarations (location, identity, payments, document uploads), app access instructions, permissions declarations, content rating and store listing assets.
4. **Functionality**: execute `docs/RIDEGO_FINAL_ACCEPTANCE_CHECKLIST.md` on two devices using artifacts from the same commit; record results, screenshots and any regressions. Check cash receipts, network recovery, RC uploads, PIN, ratings, maps, offline/online persistence.
5. **Operational security**: confirm Firebase Auth, named Firestore database `firestore-db-2`, deployed Firestore/Storage rules, least-privilege IAM, Maps key restrictions, server functions, crash monitoring, backups and rollback. Repository rule changes are not deployed automatically.
6. **Play Store staging**: upload AABs to internal testing first, install through Play, verify map/API keys and Firebase login with Play App Signing certificate, then closed testing as required by the Play account. Production promotion requires explicit owner approval.

## CI vs publication

A successful `Build RideGo Payment Test APKs` run is evidence of a **build**, not evidence of an accepted Play Store upload, working Play App Signing certificate, passed two-device acceptance or approved privacy disclosures. The source `build.gradle.kts` files use debug signing for local release builds, while the CI workflow temporarily injects permanent release signing. Keep that distinction visible.

## Decision required

**Partner package name**: choose `com.example.ridego_driver` (least disruptive to current Firebase/testing) or a final brand namespace such as `com.ridego.partner` (cleaner store identity but requires coordinated Firebase, Maps, build and installation migration). No changes to application IDs or production services are authorized by this audit.

## Automated publication evidence additions (October 2026)

The non-deploying `scripts/play-publication-gate.cjs` now also requires explicit,
boolean `true` sign-off for **cashPaymentDeviceAcceptancePassed**,
**productionFirebaseConfigurationVerified** and **playAppAccessVerified**.
These are separate from a successful APK build or Emulator run. Verify actual
cash receipt and commission results on two devices, compare deployed Firebase
rules/functions and the named `firestore-db-2` configuration with intended
release behavior, and test Play reviewer access instructions before supplying
any of these attestations. CI intentionally reports publication blockers
without blocking development builds; do not interpret a green build as
publication authorization.


## Additional publication sign-offs (October 2026)

The non-deploying Play publication gate now also requires strict boolean `true`
for `storeListingAssetsApproved`, `androidPermissionsReviewed` and
`playInternalTrackAcceptancePassed`. These are owner-reviewed attestations,
not automatic claims based on compilation. Check both apps' actual store
screenshots, icons, descriptions, permissions, disclosure text, and a Play
internal-track installation/login test using Play-distributed artifacts.
A green CI run must never be interpreted as any of these approvals.


## Release candidate identity verification

After downloading and extracting the four CI artifacts and their provenance
manifest into one directory, verify the exact commit intended for device tests:

```sh
node scripts/verify-release-candidate.cjs /path/to/extracted-artifact-root FULL_40_CHARACTER_COMMIT_SHA
```

This now fails if the manifest's source commit differs from the expected SHA,
even if all four APK/AAB hashes match the manifest. It does **not** establish
cryptographic authenticity of the manifest itself; use trusted GitHub Actions
artifacts and independently verify Android signing certificates before Play
submission. Do not confuse a passing verifier with Play Store approval.
