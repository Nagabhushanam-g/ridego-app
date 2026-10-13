# RideGo production readiness checklist

Branch: `feature/payments-from-tested-build`. This is a test plan, not evidence of completed testing.

## Partner profile (latest APK, commit 4e108a0)
- [ ] Open Personal tab; confirm correct name, phone and email.
- [ ] Edit Vehicle make/model; save; close and reopen the app; confirm value persists.
- [ ] Verify existing vehicle type and registration remain unchanged after editing.
- [ ] Open Earnings; compare accounted cash fares, commission and net to Trip History for the same accounting records. Earnings tab is all-time; Trip History has a date filter.
- [ ] Verify old confirmed rides without backend accounting are excluded from commission/net.
- [ ] Verify Documents and Bank/UPI clearly show unavailable placeholders and cannot accept sensitive details.
- [ ] Verify Sign Out and subsequent Sign In.

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
