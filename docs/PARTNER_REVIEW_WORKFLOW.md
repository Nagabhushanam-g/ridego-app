# RideGo partner review workflow (draft, not deployed)

Scope: development branch only. This document does not activate approvals, DigiLocker, or production ride gating.

## Current behavior
- Partner submits driving licence number/expiry to their own profile and RC image to Storage.
- Partner reads their own partnerVerifications/{uid} document.
- Client rules deny writes to partnerVerifications and deny self-assigned approval fields.
- The ONLINE indicator is test availability, not government approval.

## Proposed approval process
1. An authorized reviewer accesses a separate, authenticated admin workflow; ordinary Partner/Rider clients cannot review.
2. Backend checks reviewer identity and role from a server-controlled allowlist/custom claim, with revocation support.
3. Backend reads submitted documents from protected storage, checks authenticity using an approved process, and records decision with reviewer UID, timestamp, reason code and evidence references.
4. Write only through Admin SDK to partnerVerifications/{uid}; valid statuses: pending, needs_review, approved, rejected.
5. Audit each decision without logging full licence numbers, RC images or provider tokens.
6. Partner UI remains read-only; never treat an upload as approval.
7. Before production gating, enforce approved status server-side for ride acceptance and dispatch, and test races, revocations and offline clients. Keep test rides working until explicitly approved for production change.

## Security tests to add
- Partner reads own verification; cannot list all or modify any verification.
- Other signed-in users cannot read another partner's verification.
- Missing verification document returns absent, not permission denied.
- Forged reviewer identity, approval payload, or partner UID cannot bypass authorization.
- Approval revocation blocks new real ride acceptance at the backend.
- Existing ride lifecycle and cash settlement tests continue to pass.

## Release blockers
Reviewer authentication/authorization, admin UI, evidence retention, audit log policy, approval policy, backend ride gating and end-to-end tests remain unimplemented. DigiLocker requires separate official Requester approval. No Firebase deployment without explicit authorization.

## Activation blockers confirmed by Emulator tests (October 2026)

The inactive `recordPartnerReview` helper uses `tx.create` for `partnerVerifications/{partnerUid}`. This intentionally refuses to overwrite any existing record, **including a legitimate `pending` placeholder**. The real Partner approval workflow therefore cannot use this helper as-is for Partners who already have a verification document. Before activation, design a revision-aware transaction that preserves existing fields, validates the expected prior status/version, rechecks reviewer permissions and evidence, and atomically writes a separate immutable audit event. Test concurrent transitions in the Firestore Emulator.

A `partnerReviewEvidence/{evidenceId}` document with `verified: true` is **not sufficient proof of government verification** unless the server-side attestation issuer and provenance are authenticated. The collection must be writable only by a narrowly authorized backend identity. Define and validate evidence type (RC versus driving licence), source, subject binding, issuer, verification timestamp, expiry/revocation, and required evidence completeness. Do not treat manually uploaded RC images or a supplied licence number as government-verified evidence. No DigiLocker activation or production approval endpoint is authorized by these preparation commits.

Client rules explicitly deny access to reviewer, evidence and audit collections. Firebase Admin SDK bypasses these rules, so enforce IAM least privilege and issuer checks on server-side writes. Keep approval and ride gating inactive until these blockers are resolved and reviewed.
