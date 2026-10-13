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
