# RideGo DigiLocker — preparation security review (14 October 2026)

**Scope:** Development branch `feature/payments-from-tested-build`; inactive Node helpers only. No official DigiLocker Requester approval, deployed OAuth endpoint, credential exchange, issued-document retrieval or production verification has been established.

## Reviewed safeguards

| Area | Existing preparation | Remaining requirement |
| --- | --- | --- |
| Partner authorization | Callable adapter uses `request.auth.uid` and server-read `profiles/{uid}` role `driver` | Confirm account suspension, eligibility and App Check policies before activation |
| Session creation | Random 32-byte OAuth state; only SHA-256 state hash stored; 10-minute TTL | Confirm DigiLocker-specific OAuth/PKCE requirements and exact redirect URI |
| Rate limiting | Atomic Firestore transaction enforces 60-second cooldown and five attempts/hour | Add IP/device abuse controls where lawful and useful; monitor production quotas |
| Callback ownership | State hash resolves a server-owned UID, never a callback-provided UID | Implement a hardened public HTTPS callback only after provider approval |
| Replay | Firestore transaction consumes state once; Emulator concurrency tests | Validate callback races and network failures in provider sandbox |
| Error handling | Fixed error codes for unexpected Firestore failures | Ensure HTTP responses, redirects, framework logs and monitoring also redact secrets |
| Audit | Allowlisted event metadata; no raw OAuth state, code or document numbers | Configure protected audit sink, retention, access controls and monitoring |
| Retention | Bounded helper deletes sessions older than 10 minutes | Approve deletion schedule, monitoring and recovery plan before enabling |
| CI | Node unit tests, Firestore Emulator tests and APK builds | Add real provider sandbox contract and end-to-end tests |

## Release blockers / security findings

1. **No Requester approval or credentials confirmed.** Do not enable UI, exports or Firebase deployments until approval, provider requirements and redirect URI are verified.
2. **Internal callback helpers return an authorization code.** This is currently confined to inactive server-side code. A future HTTP handler MUST NOT serialize these internal results to the browser, Flutter client, logs or analytics. Exchange authorization codes only server-side and avoid storing them.
3. **No actual token exchange or document authenticity validation.** A successful callback is **not** proof of a valid DL or RC. Verification must use authorized official issued-document retrieval, field matching and a privileged review decision.
4. **Callback delivery and audit behavior need design approval.** Provider errors, malformed queries, missing sessions and unexpected exceptions must produce generic external responses; detailed request URLs may contain OAuth credentials and must not be logged. Audit events are currently only constructed through injected sinks, not persisted.
5. **Pseudonymous audit hashes remain personal-data-adjacent.** Unsalted SHA-256 UID hashes are linkable; protect audit access, minimize retention and consider a server-secret keyed HMAC before production.
6. **Cleanup is not scheduled.** Old session records persist until an approved server-only cleanup task is enabled. A 10-minute validity period does not automatically delete Firestore documents.
7. **Production policy checks remain outstanding.** Review Firestore/Storage rules, backend IAM, secret storage, privacy notice, consent text, data deletion, rate-limit operations, Partner account status and reviewer permissions.

## Required release sequence

1. Obtain official DigiLocker Requester approval and confirm sandbox/production contracts and allowed DL/RC scopes.
2. Review privacy, consent, audit retention, security and callback URL policies.
3. Implement and test server-only token exchange, official issued-document retrieval, issuer/number/expiry matching and protected review.
4. Add provider sandbox tests for consent denial, replay, wrong/expired document, partial responses, revocation and retry behavior.
5. Explicitly approve any Firebase function exports/deployment and Flutter button activation. Keep existing manual-upload workflow available.

**Review conclusion:** Current helper tests passing means only that preparation logic is validated in CI. DigiLocker verification is **not live, officially connected or approved**.
