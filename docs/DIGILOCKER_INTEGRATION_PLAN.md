# RideGo Partner — DigiLocker integration plan

Status: **Preparation only. No approved Requester credentials or live DigiLocker integration.**

## Intended Partner experience

1. Partner chooses **Verify RC with DigiLocker** or **Verify driving licence with DigiLocker**.
2. Once approved, RideGo's backend initiates a consent-based Requester session; the app opens the official authorization URL in a secure external browser.
3. Partner authenticates and explicitly consents to sharing the **government-issued** document (not an arbitrary self-uploaded file).
4. Backend validates the callback against a server-stored one-time state and session owner; exchanges authorization credentials server-side. Never trust a mobile-app success flag as proof.
5. Backend retrieves authorized issued-document metadata/data and checks issuer, document type, vehicle registration / licence number, expiry, relevant vehicle classes and commercial transport eligibility where supported.
6. Mismatch, unavailable records, expired documents and unsupported data result in **needs review**, never automatic approval.
7. A privileged review process records verified status, method, timestamp and evidence reference. The Partner client cannot write these fields.

## Prerequisites before enabling buttons

- Register RideGo as a DigiLocker **Requester** and receive approval, supported RC/DL document types, sandbox credentials, and permitted callback domains.
- Confirm applicable privacy notice, consent language, retention/deletion policy, and reviewer access control.
- Implement backend authorization and callback handling, state/nonce expiry, token protection, rate limits, audit logs, and minimal data retention.
- Add emulator and integration tests for cancellation, forged callback, expired state, document mismatch, revoked consent and repeated attempts.
- Obtain explicit deployment approval. Never put API secrets in Flutter, website source, or GitHub.
- Reassess whether separate permit, insurance, fitness, and vehicle-class checks are needed for ride-hailing eligibility.

## Current behavior

The app displays **Coming soon** information, not a clickable login or simulated verification. Existing manual RC image and licence details remain temporary, **unverified** submissions. No document or account is automatically approved.

## Official references

- https://apisetu.gov.in/digilocker
- https://api.apisetu.gov.in/
- https://directory.apisetu.gov.in/api-collection/digilocker

## Safe implementation sequence for the next build

1. **Credential readiness (blocked until approved):** obtain DigiLocker Requester approval, client ID, server-side credentials, registered redirect URI, authorized document types and sandbox access. An ordinary user's DigiLocker authorization is not a substitute for Requester approval.
2. **Backend first:** implement authenticated callable session creation and an HTTPS callback. Bind the session to Firebase Auth UID and a short-lived, single-use cryptographic state; exchange credentials only on the backend and reject replays, mismatched users and expired sessions.
3. **Consent and issued documents:** request only approved RC/DL scopes, retrieve issued-document metadata server-side, validate issuer/type/expiry and relevant matching fields, and store only minimal review metadata. Do not accept a user-uploaded DigiLocker file as proof of official retrieval.
4. **Protected review:** write verification outcomes only through privileged backend operations; preserve read-only Partner access to `partnerVerifications/{uid}` and existing manual-upload rules.
5. **Flutter integration:** enable DigiLocker buttons only after a deployed and tested backend is available; use an external secure authorization browser, display cancellation/error/pending-review states and never request DigiLocker passwords or OTPs inside RideGo.
6. **Validation:** test successful consent, denied consent, missing issued document, expired licence, wrong vehicle, forged/replayed callback, state expiry, network loss, duplicate requests, revoked consent and manual-upload fallback.
7. **Release gate:** review Firebase rules, Storage rules, function IAM/secrets and privacy requirements; deploy only with explicit project-owner approval. Test with non-production accounts before any live verification.

## Test status (13 October 2026)

- Manual DL detail entry and RC image upload have been tested by the project owner.
- GitHub contains a preparation-only DigiLocker UI and this integration plan; there is no live authorization callback or issued-document retrieval implementation in the repository.
- No live Firebase console inspection or DigiLocker Requester credential verification has been completed in this review.
- Therefore, do **not** label DigiLocker retrieval as tested, connected or verified yet.

## Backend preparation status (14 October 2026)

- Preparation-only Firebase helpers create one-time, 10-minute OAuth state sessions, store only SHA-256 state hashes, validate Partner identity using Firebase Auth and the `profiles` role, and atomically enforce a 60-second cooldown and five requests per hour.
- An inactive callable adapter maps authorization and rate-limit failures to safe error codes. It is **not exported** from `functions/index.js`.
- The internal callback coordinator resolves state hashes to a unique server-owned session, rejects malformed/missing/replayed/expired states, and consumes the session transactionally before any future token exchange. **No public HTTP callback or DigiLocker API call exists.**
- Bounded expired-session cleanup is implemented as an inactive helper, not a scheduled function. The cleanup uses `createdAtMs` and deletes expired sessions in batches of up to 500; an operator must plan scheduling, monitoring, and deletion policy before enabling it.
- GitHub CI runs Node unit tests and Firestore Emulator tests for concurrent callbacks, session quota, and cleanup. Passing tests validate local logic, **not** official DigiLocker integration or production readiness.
- The OAuth authorization code currently appears only as an internal server-side callback result; future integration must keep it out of logs, client responses and persistent documents, and handle provider failures securely.
- **Before activation:** confirm Requester approval, exact provider OAuth requirements and redirect URI, approved scopes, secrets management, consent/privacy and retention requirements, production IAM/rules, abuse protection, end-to-end sandbox testing and explicit deployment approval.
