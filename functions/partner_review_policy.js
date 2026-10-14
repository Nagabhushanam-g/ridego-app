'use strict';

// Inactive server-only policy helper. Never export from functions/index.js
// until the reviewer identity and production approval workflow are authorized.
const STATUSES = new Set(['pending', 'needs_review', 'approved', 'rejected']);
const REASONS = new Set([
  'documents_incomplete', 'document_mismatch', 'expired_document',
  'manual_review', 'verification_complete'
]);
const UID = /^[A-Za-z0-9_-]{1,128}$/;

function preparePartnerReviewDecision({reviewerUid, reviewerAuthorized, partnerUid, status, reasonCode, now}) {
  if (typeof reviewerUid !== 'string' || !UID.test(reviewerUid) ||
      reviewerAuthorized !== true) {
    return {ok: false, errorCode: 'permission-denied'};
  }
  if (typeof partnerUid !== 'string' || !UID.test(partnerUid) ||
      reviewerUid === partnerUid) {
    return {ok: false, errorCode: 'invalid-argument'};
  }
  if (!STATUSES.has(status) || !REASONS.has(reasonCode) ||
      (status === 'approved' && reasonCode !== 'verification_complete') ||
      (status === 'rejected' && reasonCode === 'verification_complete')) {
    return {ok: false, errorCode: 'invalid-argument'};
  }
  if (!Number.isSafeInteger(now) || now < 0) {
    return {ok: false, errorCode: 'invalid-argument'};
  }
  return {
    ok: true,
    partnerUid,
    record: {
      status,
      reasonCode,
      reviewedBy: reviewerUid,
      reviewedAtMs: now
    }
  };
}

module.exports = {preparePartnerReviewDecision};
