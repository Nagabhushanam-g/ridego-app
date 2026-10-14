'use strict';

// Inactive, server-only revision-aware transition helper. Not exported by index.js.
// Never accept reviewer authorization, evidence verification or revision from a client.
const {preparePartnerReviewDecision} = require('./partner_review_policy');
const ID = /^[A-Za-z0-9_-]{1,128}$/;

async function transitionPendingPartnerReview({db, decision, evidenceIds, now, expectedRevision}) {
  if (!db || typeof db.runTransaction !== 'function' ||
      !decision || decision.ok !== true || !decision.record ||
      !Number.isSafeInteger(now) || now < 0 ||
      !Number.isSafeInteger(expectedRevision) || expectedRevision < 0 ||
      !Array.isArray(evidenceIds) || evidenceIds.length > 10 ||
      !evidenceIds.every(id => typeof id === 'string' && ID.test(id)) ||
      new Set(evidenceIds).size !== evidenceIds.length) {
    return {ok: false, errorCode: 'invalid-argument'};
  }
  const policy = preparePartnerReviewDecision({
    reviewerUid: decision.record.reviewedBy, reviewerAuthorized: true,
    partnerUid: decision.partnerUid, status: decision.record.status,
    reasonCode: decision.record.reasonCode, now
  });
  if (!policy.ok || decision.record.reviewedAtMs !== now ||
      !['approved', 'rejected', 'needs_review'].includes(policy.record.status) ||
      (policy.record.status === 'approved' && evidenceIds.length === 0)) {
    return {ok: false, errorCode: 'invalid-argument'};
  }
  const partnerUid = policy.partnerUid;
  const reviewerUid = policy.record.reviewedBy;
  const profileRef = db.collection('profiles').doc(partnerUid);
  const reviewerRef = db.collection('partnerReviewers').doc(reviewerUid);
  const verificationRef = db.collection('partnerVerifications').doc(partnerUid);
  const auditRef = db.collection('partnerReviewAudit').doc();
  const evidenceRefs = evidenceIds.map(id => db.collection('partnerReviewEvidence').doc(id));

  try {
    await db.runTransaction(async tx => {
      // All transaction reads precede writes, including evidence reads.
      const [profile, reviewer, previous, ...evidence] = await Promise.all([
        tx.get(profileRef), tx.get(reviewerRef), tx.get(verificationRef),
        ...evidenceRefs.map(ref => tx.get(ref))
      ]);
      if (!profile.exists || profile.get('role') !== 'driver' ||
          !reviewer.exists || reviewer.get('active') !== true ||
          reviewer.get('role') !== 'partner_reviewer') {
        throw new Error('permission-denied');
      }
      if (!previous.exists || previous.get('status') !== 'pending' ||
          (previous.get('reviewRevision') ?? 0) !== expectedRevision) {
        throw new Error('stale-or-ineligible-review');
      }
      if (policy.record.status === 'approved' && evidence.some(doc =>
        !doc.exists || doc.get('partnerUid') !== partnerUid ||
        doc.get('verified') !== true || doc.get('revoked') === true)) {
        throw new Error('evidence-not-verified');
      }
      const update = {
        status: policy.record.status, reasonCode: policy.record.reasonCode,
        reviewedBy: reviewerUid, reviewedAtMs: now, evidenceIds,
        reviewRevision: expectedRevision + 1
      };
      tx.update(verificationRef, update);
      tx.create(auditRef, {
        partnerUid, previousStatus: 'pending', previousRevision: expectedRevision,
        ...update, event: 'partner_review_transition'
      });
    });
    return {ok: true};
  } catch (_) {
    return {ok: false, errorCode: 'failed-precondition'};
  }
}

module.exports = {transitionPendingPartnerReview};
