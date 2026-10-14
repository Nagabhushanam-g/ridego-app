'use strict';

// Inactive server-only transaction helper. No production export.
// Caller must provide a decision prepared by trusted reviewer authorization.
// Evidence is represented only by server-validated opaque reference IDs.
const {preparePartnerReviewDecision} = require('./partner_review_policy');
const ID = /^[A-Za-z0-9_-]{1,128}$/;
const STATUS = new Set(['pending', 'needs_review', 'approved', 'rejected']);

async function recordPartnerReview({db, decision, evidenceIds, now}) {
  if (!db || typeof db.runTransaction !== 'function' ||
      !decision || decision.ok !== true ||
      !ID.test(decision.partnerUid || '') ||
      !ID.test(decision.record?.reviewedBy || '') ||
      decision.partnerUid === decision.record.reviewedBy ||
      !STATUS.has(decision.record.status) ||
      !Number.isSafeInteger(now) || now < 0 ||
      decision.record.reviewedAtMs !== now ||
      !Array.isArray(evidenceIds) || evidenceIds.length > 10 ||
      !evidenceIds.every(id => typeof id === 'string' && ID.test(id)) ||
      new Set(evidenceIds).size !== evidenceIds.length ||
      (decision.record.status === 'approved' && evidenceIds.length === 0)) {
    return {ok: false, errorCode: 'invalid-argument'};
  }

  const partnerRef = db.collection('profiles').doc(decision.partnerUid);
  const reviewerRef = db.collection('partnerReviewers').doc(decision.record.reviewedBy);
  const verificationRef = db.collection('partnerVerifications').doc(decision.partnerUid);
  const auditRef = db.collection('partnerReviewAudit').doc();
  try {
    await db.runTransaction(async tx => {
      const [reviewer, profile, previous] = await Promise.all([
        tx.get(reviewerRef), tx.get(partnerRef), tx.get(verificationRef)
      ]);
      if (!reviewer.exists || reviewer.get('active') !== true ||
          reviewer.get('role') !== 'partner_reviewer' ||
          !profile.exists || profile.get('role') !== 'driver') {
        const err = new Error('not_authorized');
        err.code = 'permission-denied';
        throw err;
      }
      // Revalidate the complete decision against server-checked reviewer authority.
      const checked = preparePartnerReviewDecision({
        reviewerUid: decision.record.reviewedBy,
        reviewerAuthorized: true,
        partnerUid: decision.partnerUid,
        status: decision.record.status,
        reasonCode: decision.record.reasonCode,
        now
      });
      if (!checked.ok) {
        const err = new Error('invalid_review_decision');
        err.code = 'invalid-argument';
        throw err;
      }
      // First decision only. Subsequent changes require a separately designed
      // revision-aware review flow; transactions retry against concurrent writes.
      if (previous.exists) {
        const err = new Error('review_already_exists');
        err.code = 'already-exists';
        throw err;
      }
      const record = {
        status: decision.record.status,
        reasonCode: decision.record.reasonCode,
        reviewedBy: decision.record.reviewedBy,
        reviewedAtMs: now,
        evidenceIds
      };
      tx.create(verificationRef, record);
      tx.create(auditRef, {
        partnerUid: decision.partnerUid,
        ...record,
        event: 'partner_review_decision'
      });
    });
    return {ok: true};
  } catch (_) {
    return {ok: false, errorCode: 'failed-precondition'};
  }
}

module.exports = {recordPartnerReview};
