'use strict';

// Inactive adapter for a future authenticated administrator endpoint.
// The authorization decision must be supplied by a trusted server-side lookup,
// never from request.data, request headers, or a client-controlled role field.
const {preparePartnerReviewDecision} = require('./partner_review_policy');

async function prepareAuthenticatedPartnerReview({request, db, now}) {
  const reviewerUid = request?.auth?.uid;
  if (typeof reviewerUid !== 'string' || !/^[A-Za-z0-9_-]{1,128}$/.test(reviewerUid)) {
    return {ok: false, errorCode: 'unauthenticated'};
  }
  if (!db || typeof db.collection !== 'function') {
    return {ok: false, errorCode: 'internal'};
  }
  try {
    // Reviewer membership is a server-controlled document; client rules must
    // deny all reads and writes. No privilege comes from request.data.
    const reviewer = await db.collection('partnerReviewers').doc(reviewerUid).get();
    const authorized = reviewer.exists &&
      reviewer.get('active') === true &&
      reviewer.get('role') === 'partner_reviewer';
    if (!authorized) return {ok: false, errorCode: 'permission-denied'};

    const decision = preparePartnerReviewDecision({
      reviewerUid,
      reviewerAuthorized: authorized,
      partnerUid: request?.data?.partnerUid,
      status: request?.data?.status,
      reasonCode: request?.data?.reasonCode,
      now
    });
    if (!decision.ok) return decision;

    const profile = await db.collection('profiles').doc(decision.partnerUid).get();
    if (!profile.exists || profile.get('role') !== 'driver') {
      return {ok: false, errorCode: 'failed-precondition'};
    }
    // No Firestore writes: review evidence and audit must be implemented first.
    return decision;
  } catch (_) {
    return {ok: false, errorCode: 'internal'};
  }
}

module.exports = {prepareAuthenticatedPartnerReview};
