# Partner GO ONLINE verification rollout — preparation only

Status: **NOT ENABLED**. This document is a design checklist, not deployment authorization.

## Existing live behavior (reviewed on the feature branch)

- `driver/lib/main.dart` writes `users/{uid}.isOnline` directly from the Flutter client in `_recordAvailability` (approximately lines 417–425).
- The GO ONLINE button calls `toggle`, then `_recordAvailability(true)` and starts the ride-request listener (approximately lines 427–474).
- On app restart, `_restoreOnlinePreference` can call `_recordAvailability(true)` again based on SharedPreferences (approximately lines 170–185).
- The current `isOnline` flag is not a heartbeat-backed presence guarantee.
- Thus, checking only the GO ONLINE button is insufficient: restart recovery, other client versions, and direct Firestore writes can bypass it.

## Required production migration before enforcement

1. Identify all client/server writes and reads of `users/{uid}.isOnline`, driver matching, request listeners, and Firestore rules for the **named database `firestore-db-2`**. Verify actual production paths and auth roles.
2. Preserve existing drivers with an explicitly approved migration/backfill policy. Do not turn on enforcement merely because new verification documents are absent for legacy Partners.
3. Add an authenticated server endpoint for going online that uses the actual Firebase Auth UID, not a caller-provided UID, and performs an atomic transaction checking approval, RC, DL, expiry, revocation, revision and writing server-owned eligibility/presence state. Validate source/issuer trust and the official DigiLocker consent flow.
4. Move every path that can set a driver online (including SharedPreferences restart restoration) through the server gate. Keep GO OFFLINE and active-ride recovery safe. Prevent older clients from bypassing the gate with appropriately tested Firestore security rules.
5. Make matching/dispatch depend on **current** server eligibility (not a stale `authorized: true` flag). Design heartbeat expiry, revocation/expiry rechecks, and a safe response when evidence changes during an active trip.
6. Add Firestore Emulator tests for concurrent online requests, expiry at boundary, revocation after authorization, profile mismatch, stale revision, offline mode, restart recovery and direct client write denial. Verify app UI and regression tests on two devices.
7. Deploy only after DigiLocker Requester onboarding, callback domain, privacy/consent handling, credential management and explicit approval. Roll out behind a server-side feature flag with monitoring and rollback.

## Current preparation helpers

- `partner_online_eligibility.js`: default legacy compatibility policy.
- `partner_online_assessment.js`: read-only RC/DL assessment.
- `partner_online_transaction.js`: inactive transactional authorization record (not live presence).
- `partner_online_grant_check.js`: checks grant against current RC/DL evidence at time of use.
- `partner_review_recheck.js`: can mark approved Partners `needs_review` and revoke a grant atomically when invoked.

**Important:** None of these helpers is exported as a deployed callable in `functions/index.js`. Existing app GO ONLINE behavior is unchanged. The preparation code is not yet a complete enforcement system; in particular, a read-only check followed by a separate dispatch operation has a time-of-check/time-of-use race. Do not enable enforcement without integrating the gate with actual presence and dispatch state.

## Compatibility test baseline (October 2026)

The Firestore Emulator suite now explicitly tests the current behavior of
`users/{uid}.isOnline`: a signed-in Partner can write their own online/offline
choice, another user cannot write it, and the Partner cannot replace their
`uid` with another account's identifier. This is a **baseline, not a security
endorsement**: an older client can still set its own online flag without a
server verification gate. The tests intentionally keep that path working until
we have a tested, explicit migration and enforcement decision.

**Cutover criterion:** do not restrict `users/{uid}.isOnline` until the Partner
app's button and restart recovery use the new server endpoint, older app
versions have a supported upgrade path, and dispatch/presence rules have
matching integration tests. Then replace these legacy-baseline expectations
with tests that reject direct client `isOnline: true` writes.

## Inactive atomic dispatch prototype

`functions/partner_dispatch_transaction.js` is a preparation-only transaction
that rechecks the requested ride, driver role, approved review revision,
server authorization expiry, and current RC/DL evidence before updating the
ride to `accepted`. It is **not exported or deployed**; existing client-side
acceptance remains unchanged. Its Emulator tests cover inactive mode, revoked
evidence, simultaneous acceptance attempts, and an expired grant.

**Do not activate this prototype as-is.** It does not yet verify heartbeat-backed
online presence, ensure the driver has no other active ride, validate all ride
assignment policy fields, or migrate older client versions. A server-owned
assignment endpoint and tested Firestore rules must replace the direct client
acceptance path together. A real deployment also needs a review of trusted
clock handling and transaction-time expiry boundaries.
