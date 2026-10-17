'use strict';

// Preparation-only, not scheduled or exported from functions/index.js.
// Rechecks the original evidence references; it never accepts client claims.
const {validatePartnerEvidence} = require('./partner_review_evidence');
const ID = /^[A-Za-z0-9_-]{1,128}$/;

async function recheckApprovedPartnerEvidence({db, partnerUid, now = Date.now()}) {
  if (!db || typeof db.runTransaction !== 'function' ||
      typeof partnerUid !== 'string' || !ID.test(partnerUid) ||
      !Number.isSafeInteger(now) || now < 0) {
    return {ok: false, errorCode: 'invalid-argument'};
  }
  const verificationRef = db.collection('partnerVerifications').doc(partnerUid);
  const auditRef = db.collection('partnerReviewAudit').doc();
  const onlineRef = db.collection('partnerOnlineAuthorizations').doc(partnerUid);
  try {
    return await db.runTransaction(async tx => {
      const [verification, onlineAuthorization] = await Promise.all([
        tx.get(verificationRef), tx.get(onlineRef)
      ]);
      if (!verification.exists || verification.get('status') !== 'approved') {
        return {ok: false, errorCode: 'not-approved'};
      }
      const ids = verification.get('evidenceIds');
      const validIds = Array.isArray(ids) && ids.length >= 2 && ids.length <= 10 &&
        ids.every(id => typeof id === 'string' && ID.test(id)) &&
        new Set(ids).size === ids.length;
      // Malformed references are invalid evidence, not a reason to leave an
      // approved Partner active. Avoid reading attacker-controlled paths.
      const evidence = validIds ? await Promise.all(ids.map(id =>
        tx.get(db.collection('partnerReviewEvidence').doc(id)))) : [];
      const types = new Set();
      const valid = validIds && evidence.every(doc => {
        if (!validatePartnerEvidence(doc, {partnerUid, now})) return false;
        types.add(doc.get('documentType'));
        return true;
      });
      if (valid && types.has('registration_certificate') && types.has('driving_licence')) {
        return {ok: true, status: 'approved'};
      }
      const revision = verification.get('reviewRevision') ?? 0;
      if (!Number.isSafeInteger(revision) || revision < 0 ||
          revision >= Number.MAX_SAFE_INTEGER) throw new Error('invalid-revision');
      tx.update(verificationRef, {
        status: 'needs_review', reasonCode: 'documents_incomplete',
        reviewRevision: revision + 1, evidenceRecheckedAtMs: now
      });
      if (onlineAuthorization.exists && onlineAuthorization.get('authorized') === true) {
        tx.update(onlineRef, {
          authorized: false, invalidatedAtMs: now,
          invalidationReason: 'document_evidence_invalid'
        });
      }
      tx.create(auditRef, {
        partnerUid, event: 'partner_evidence_invalidated',
        previousStatus: 'approved', status: 'needs_review',
        previousRevision: revision, reviewRevision: revision + 1,
        checkedAtMs: now
      });
      return {ok: true, status: 'needs_review'};
    });
  } catch (_) {
    return {ok: false, errorCode: 'failed-precondition'};
  }
}

module.exports = {recheckApprovedPartnerEvidence};
