# RideGo production readiness checklist

Branch: `feature/payments-from-tested-build`. This is a test plan, not evidence of completed testing.

## Partner profile (latest APK, commit 4e108a0)
- [ ] Open Personal tab; confirm correct name, phone and email.
- [x] Edit Vehicle make/model; save; close and reopen the app; confirm value persists (user confirmed October 13, 2026).
- [ ] Verify existing vehicle type and registration remain unchanged after editing.
- [x] Open Earnings and verify displayed cash fares, commission and Partner net (user confirmed October 13, 2026). Earnings tab is all-time; Trip History has a date filter. Detailed cross-check against backend ledger remains pending.
- [ ] Verify old confirmed rides without backend accounting are excluded from commission/net.
- [ ] Verify Documents and Bank/UPI clearly show unavailable placeholders and cannot accept sensitive details.
- [ ] Verify Sign Out and subsequent Sign In.

## Next device test: new cash ride and idempotency
- [ ] Complete a fresh cash ride and record the exact fare, receipt ID and Partner commission/net from Trip History.
- [ ] Compare commission with 10% of fare and Partner net with fare minus commission (allow paise rounding).
- [ ] Confirm the Rider sees payment received and the Partner's accounted ride count increases exactly once.
- [ ] Reopen the ride history; verify no duplicate receipt or commission is shown. Backend duplicate-write prevention needs separate automated/integration verification.

## Rider and Partner end-to-end
- [x] Fresh cash ride: completed, Partner confirmed cash, Rider saw paid, rated trip; screenshots reviewed October 12, 2026.
- [ ] Fresh second cash ride: verify receipt ID, 10% commission and 90% net on the exact ride.
- [ ] Check cash confirmation cannot be repeated; no duplicate receipt or commission.
- [ ] Verify payment cannot be confirmed by another Partner or before completion.
- [ ] Test PIN verification, arrival, start, completion, cancellation and no-network recovery.
- [ ] Test Rider and Partner history filters, permissions and historical data handling.
- [ ] Test notification behavior in foreground, background and after app restart.
- [ ] Test GPS/maps, location permissions and routing on actual devices.

## Production gates
- [ ] Review and deploy final Firestore rules, indexes and Cloud Functions intentionally.
- [ ] Review payment settlement, refund/dispute handling and commission reconciliation; current cash settlement is NOT implemented.
- [ ] Complete secure Partner document verification and payout setup or explicitly restrict launch scope until available.
- [ ] Review privacy, data retention, account deletion, support and applicable legal requirements.
- [ ] Test clean install and upgrade, release signing, Play Store compliance, crash monitoring and rollback plan.
- [ ] Confirm both apps' production release candidates are approved.

Only after the production gates are satisfied should the official RideGo website project begin.
