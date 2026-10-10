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
