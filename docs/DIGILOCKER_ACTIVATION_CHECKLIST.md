# RideGo DigiLocker activation checklist

**Status: BLOCKED — preparation only.** This checklist is not deployment approval. DigiLocker helpers are not exported from `functions/index.js`; the Partner app's verification buttons must remain inactive.

## 1. Provider approval and contracts (mandatory)

- [ ] Official DigiLocker Requester onboarding and authorization confirmed for RideGo's legal entity.
- [ ] Approved callback domains and exact redirect URI documented, separately for sandbox and production.
- [ ] Official OAuth endpoints, token authentication method, PKCE requirements, permitted scopes, and state handling confirmed from the approved provider documentation.
- [ ] Official issued DL and RC document APIs, issuer identifiers, response schemas, expiry/revocation behavior, and applicable rate limits confirmed.
- [ ] Provider credentials stored in approved server-side secret management; **never** in Flutter, GitHub, logs, Firestore client-readable documents, or chat.

## 2. Security, privacy, and authorization

- [ ] Partner identity and eligibility validated server-side from Firebase Auth and the trusted profile, including suspended/deactivated accounts.
- [ ] Consent copy, purpose limitation, privacy notice, retention/deletion policy, and applicable legal requirements approved.
- [ ] Public callback endpoint protected by strict state validation, one-time consumption, bounded input sizes, generic external errors, and safe redirect responses.
- [ ] Authorization codes exchanged **only server-side**; callback results containing codes never serialized to browsers or mobile apps.
- [ ] No OAuth tokens, raw authorization states, identity documents, licence numbers or callback URLs written to logs/analytics.
- [ ] Production audit sink configured with restricted access, bounded retention, monitoring, and a server-secret keyed correlation strategy if owner correlation is required.
- [ ] Cleanup job, retry policy, alerts, and incident response reviewed. Confirm session expiration and deletion independently.
- [ ] Firebase IAM, Firestore rules for named database `firestore-db-2`, Storage rules and App Check enforcement reviewed.

## 3. Verification behavior

- [ ] Verify **issued** DL and RC using official provider results, not merely successful OAuth consent.
- [ ] Compare required identifiers, name/vehicle ownership where appropriate, issuer status, document expiry and revocation indicators using approved matching rules.
- [ ] Persist only the minimal verification decision and metadata with access controls; define re-verification and manual review procedures.
- [ ] Keep existing manual RC image and DL number/expiry workflow available during rollout.
- [ ] Define clear user-visible outcomes for consent denied, missing document, mismatch, expired document, provider outage, and pending review.

## 4. Testing and rollout gates

- [ ] Provider sandbox: success, denial, malformed callback, unknown state, expired state, replay, concurrent callback, provider timeout, invalid token and partial document.
- [ ] Test mobile app killed/reopened, offline recovery, retry throttling and account switching.
- [ ] Confirm emulator tests, security validation, Flutter analysis and Rider/Partner APK builds all pass.
- [ ] Confirm no regression to booking, PIN/start-trip, cash confirmation, earnings, ratings, trip history, manual document upload or Partner profile.
- [ ] Review privacy/security and approve **specific** backend endpoint exports, Firebase deployment, callback domain registration, and Partner UI activation.
- [ ] Roll out first to limited test Partners with monitoring and a documented rollback switch; only then consider broader production activation.

## Release decision

**Do not deploy or enable DigiLocker** until the mandatory items above are completed and a new explicit deployment authorization is given. Passing unit tests and producing APKs do not establish official provider approval or document authenticity.

References: `docs/DIGILOCKER_INTEGRATION_PLAN.md`, `docs/DIGILOCKER_SECURITY_REVIEW.md`.
