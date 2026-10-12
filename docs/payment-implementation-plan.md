# RideGo payment implementation plan

Source baseline: dev/base112-clean (tested PIN verification, completed-trip rating UI).
This branch is for payment work; do not deploy until client/server and rules are reviewed together.

## Existing behavior
- Rider keeps a completed trip visible until BACK TO HOME.
- Driver currently clears the ride after marking it completed.
- Firestore rideRequests stores fare, riderId, driverId and status, but no protected payment state.
- Firestore rules restrict trip updates to specific fields; do not allow clients to write a paid flag.
- Driver PIN is validated against riderTripPins by security rules.

## Phase 1: Cash
- Keep ride status 'completed' distinct from paymentStatus ('pending', 'paid').
- Create a server-side, authenticated cash confirmation operation restricted to the assigned Partner and a completed ride.
- Validate fare from the stored ride, never from client-supplied amount.
- Use a transaction to set paymentMethod='cash', paymentStatus='paid', paidAt, collectedBy, and a stable receipt reference once.
- Reject repeat or conflicting payment confirmations.
- Show Rider: Cash pending / Cash received, Partner: Confirm cash received, and both: receipt.
- Keep payment records and partner earnings ledger server-controlled, immutable and idempotent.
- Avoid a client-writeable 'paid' field in Firestore rules.
- Test unauthorized users, duplicate taps, network retries, cancellation and offline behavior.

## Phase 2: UPI
- Use a licensed payment service provider for collection and Partner settlement as supported by its India product and onboarding.
- Initiate payment server-side for the authoritative ride amount; persist gateway order ID.
- Never treat a UPI deep link return or screenshot as proof of payment.
- Verify signed provider webhook server-side, cross-check order, amount, currency and status, and make updates idempotent.
- Support pending, failed, expired, paid and refund/settlement reconciliation.

## Release gates
- Verify production Firestore database/rules alignment before deployment.
- Test completed trip recovery, ratings, PIN validation, cash receipt and UPI failure cases.
- Build both APKs and test on devices before merging.


## Commission and earnings accounting (proposed, not activated)
- Commission policy v1 is approved at 10% (1,000 basis points), configured server-side. Changes require a new version.
- Snapshot the applicable policy onto each paid ride so later rate changes cannot rewrite past earnings.
- Store amounts in integer INR minor units when introducing online settlement; avoid floating-point commission math.
- On a verified payment, create one idempotent ledger entry keyed by ride ID, recording gross fare, commission, net Partner earnings, collection method, and any settlement liability.
- Cash collected by the Partner is not the same as a platform payout. The ledger must separately track what the Partner holds and what is owed to RideGo.
- Treat trips predating payment confirmation as unverified; never backfill them as paid based on completion alone.
- Protect commission settings and earnings ledger from all client writes.
- Do not activate deductions until the commission percentage, rounding rule, tax handling, and settlement process have been approved.

## Commission implementation status (test branch only)
- New cash confirmations write a server-owned `partnerEarnings/{rideId}` ledger record in the same transaction as the payment receipt, including integer paise gross, commission and net amounts.
- The ride document also stores the snapshot amounts for Partner history display. Existing paid trips are not silently backfilled.
- Ledger settlement status is `not_settled`; no automatic money transfer, collection, payout, or deduction occurs.
- **Deployment gate:** review and test Firestore security rules, duplicate confirmations, existing receipts, commission rounding and Partner display before deploying the function. The GitHub test build does not deploy Firebase.

## Pre-deployment approval and test checklist (10% cash commission)

Deployment is **not** authorized by a successful APK build. The existing `.github/workflows/deploy-cash-payment.yml` workflow deploys automatically when its own workflow file is pushed to the feature branch; do not edit or push that workflow merely to prepare deployment. Request explicit approval immediately before triggering any production Firebase function deployment.

1. Confirm the deployed Firebase project is `ridego-af7c3` and the function reads named database `firestore-db-2`.
2. Confirm current rider and Partner APKs create rides with `paymentRequired: true`; completed historical rides lacking this field remain non-payable.
3. Verify the caller is authenticated, has a Partner profile, and is assigned to the completed ride. Wrong users and incomplete rides must be rejected.
4. Confirm ₹100 produces ₹10.00 commission and ₹90.00 Partner net; ₹398 produces ₹39.80 commission and ₹358.20 Partner net. Verify amounts in integer paise.
5. Confirm the same transaction writes the receipt, one `partnerEarnings/{rideId}` ledger document, and the ride payment/commission snapshot.
6. Confirm retrying the same cash confirmation returns an already-confirmed result without a second receipt or ledger record. Test simultaneous double taps and network retries.
7. Confirm legacy test rides cannot be cash-confirmed; they remain in history and do not appear as active payment requests.
8. Confirm client Firestore rules do not permit direct writes to receipts, earnings ledger, or ride payment/commission fields. The Admin SDK writes these server-side.
9. Confirm cash settlement is **not automated**. `settlementStatus: not_settled` is a bookkeeping marker, not a transfer.
10. Only after explicit approval, deploy the single `confirmCashPayment` function, verify its logs, and run one fresh test trip end-to-end on both devices. Preserve rollback details for the prior function version.

**Compatibility warning:** Newly created rides use `paymentRequired: true`. Any older APK still creating rides without this marker will be treated as legacy and will not be eligible for cash confirmation. Both test devices must use the latest APKs before testing.
