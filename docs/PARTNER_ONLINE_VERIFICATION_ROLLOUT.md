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
