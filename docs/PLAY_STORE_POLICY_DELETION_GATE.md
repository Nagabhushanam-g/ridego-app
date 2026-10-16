# RideGo Play Store policy and account deletion gate

Status: **BLOCKING — not ready for public Play Store submission**. This is a review checklist, not a representation that these capabilities exist.

## Verified from source (2026-10-16)

- `website/privacy.html` prominently says **Draft privacy information — review required**, describes itself as a website preview, and does not provide a finalized privacy contact, retention schedule or deletion procedure. Do not submit it as a final public privacy policy.
- The repository does not currently contain an obvious dedicated public account-deletion request page or documented, implemented account deletion workflow. Absence from the repository does not prove no external workflow exists; verify independently before store submission.
- Partner RC and driving licence information, location, ride history, payment status, and device tokens are sensitive disclosure areas that require a verified data inventory.
- DigiLocker verification is explicitly **not active**. Do not claim official verification or publish consent/retention statements as if it is live.

## Required implementation and owner decisions

1. Choose a monitored support/privacy contact and establish an authenticated in-app account deletion request path for both Rider and Partner. Provide a public web URL where users can request account and associated data deletion **without reinstalling the app**. Confirm Play Console's current account deletion requirements.
2. Define deletion processing: verify requester identity, disable login/dispatch as appropriate, determine which Firebase Auth, Firestore, Storage, notification tokens and third-party data must be deleted, and document exceptions for legally required records (including ride/payment and compliance records). Do not erase active trip or payment evidence without a reviewed retention policy.
3. Implement server-authorized, auditable, idempotent deletion handling; deny cross-account deletion, repeated destructive calls and unauthorized data access. Add Emulator tests for request authorization, retry behavior, active-ride safeguards and eventual cleanup.
4. Replace the draft website privacy notice with an approved public policy that accurately covers Rider and Partner behavior, permissions, precise/background location use, collection/sharing, retention, security, contact and deletion rights. Make the final policy publicly reachable over HTTPS.
5. Review and publish Play Console Data safety forms separately for both packages; confirm what is collected vs shared and whether collection is optional. Prepare app access instructions, permissions disclosures, screenshots, icons and contact details.
6. Verify the actual public URLs, links from both apps, response workflow and deletion behavior before promoting beyond internal testing.

## Do not prematurely enable

Do not advertise account deletion as functional before the backend workflow and support process are ready. Do not auto-delete user data or modify production Auth/Firestore/Storage without explicit approval. Keep `website/privacy.html` labeled as a draft until legal/product review is completed.

## Release tracking

- **AAB signing and package identity:** automated checks present; verify actual artifact signatures and Play App Signing.
- **Public privacy policy:** blocked — existing source is a draft.
- **Account deletion (app + web):** blocked — requires implementation and owner-approved retention decisions.
- **Partner package ID:** owner decision still required before first upload.
- **Two-device final acceptance:** pending.
- **Production deployment / Play Console upload:** not authorized.


## Request queue lifecycle and retention guardrails

The preparation-only request handler creates `accountDeletionRequests/{authUid}`
with `pending_review`; it does **not** delete Auth, Firestore, Storage, ride
history, payment receipts, or documents. It blocks requests during active
rides, and a completed ride can be queued for later review. A completed ride
may still have unsettled payment or legally required records, so queueing is
**not approval for deletion**. Before implementing the processor, an owner
must approve a retention matrix and specify how outstanding cash/UPI,
commission, dispute, tax and fraud records are handled. The processor must
recheck active trips and unsettled obligations at execution time, not rely
solely on conditions when the request was queued.

The expanded Emulator suite covers Rider and Partner active ride states,
completed rides, invalid reasons, cross-account denial and idempotent retries.
No endpoint is deployed and no public deletion workflow is claimed.
