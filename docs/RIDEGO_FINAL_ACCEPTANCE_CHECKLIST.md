# RideGo final two-device acceptance checklist

**Status:** Manual acceptance pending. Use test accounts, a safe non-production payment scenario, and the latest validated Rider and Partner APKs. Automated CI does **not** prove the end-to-end experience on devices.

## Before starting

- [ ] Record tested commit, workflow run IDs, Rider APK version and Partner APK version.
- [ ] Install Rider and Partner on separate Android devices; confirm both connect to the intended Firebase environment and named Firestore database `firestore-db-2`.
- [ ] Verify both accounts sign in, profiles load, and maps show valid locations.
- [ ] Confirm DigiLocker buttons say **Coming soon** and cannot initiate OAuth.
- [ ] Confirm test trip fare, test Partner identity and test device permissions.

## Rider + Partner ride lifecycle

- [ ] Partner goes ONLINE, closes and reopens the app; ONLINE status persists.
- [ ] Rider chooses destination, sees route/fare, and books a ride.
- [ ] Partner accepts once; another Partner cannot accept the same request.
- [ ] Rider sees accepted status and assigned Partner/vehicle information.
- [ ] Partner marks ARRIVED; Rider displays the matching state.
- [ ] Rider displays PIN; Partner enters correct PIN to start trip.
- [ ] Incorrect PIN cannot start trip; reopening either app preserves current trip state.
- [ ] Partner completes trip; both apps show completed state and consistent history.
- [ ] Rider and Partner ratings are available as designed.

## Cash and earnings

- [ ] Completed cash ride permits assigned Partner to confirm cash received.
- [ ] Repeated confirmation does not create a second receipt or commission.
- [ ] Rider and Partner receipts/history agree on fare and payment status.
- [ ] For a **₹419** test ride: commission **₹41.90**, Partner net **₹377.10**.
- [ ] Historical rides cannot be newly cash-confirmed.
- [ ] UPI-selected rides cannot be cash-confirmed; do not claim UPI is live unless separately verified.
- [ ] Earnings date filters and per-trip details agree with confirmed receipts.

## Partner documents

- [ ] Personal, Vehicle, Earnings and Documents sections load after reopening.
- [ ] Save a valid DL number and future expiry; reload and verify persistence.
- [ ] Invalid DL number or expired licence is rejected.
- [ ] Upload one JPG or PNG RC image no larger than 5 MB; reload and confirm submitted state.
- [ ] Reject PDF, unsupported content types and oversized files; verify owner-only access.
- [ ] Submission remains **pending verification**, not automatically approved.
- [ ] A different signed-in account cannot read or replace the Partner's RC.
- [ ] DigiLocker is not requested, authorized or treated as verification.

## Network and recovery

- [ ] Turn mobile data/Wi-Fi OFF before booking: clear offline state, no unintended new ride.
- [ ] Disconnect during an accepted/started trip; reopen both apps, reconnect, and verify state sync.
- [ ] Repeat trip completion/cash confirmation after a network interruption; no duplicate writes.
- [ ] Check no private document data, PIN, OAuth state or payment secrets appear in logs or notifications.

## Release gate

- [ ] All automated validations and APK builds pass on the **same commit**.
- [ ] Record any failures with exact app version, test step, timestamp and screenshots.
- [ ] Fix and retest blockers; repeat payment, document and ride smoke tests after fixes.
- [ ] Obtain explicit approval before Play Store publication or Firebase production deployment.

**Do not mark this checklist passed until tests have actually been performed on devices.**
