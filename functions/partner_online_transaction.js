'use strict';

// Inactive, never exported from functions/index.js. Future activation requires
// explicit rollout approval and a server-authorized online state owner.
const {validatePartnerEvidence} = require('./partner_review_evidence');
const ID = /^[A-Za-z0-9_-]{1,128}$/;

async function authorizePartnerOnlineTransaction({db, partnerUid, now = Date.now(), enforcementEnabled = false}) {
  if (!db || typeof db.runTransaction !== 'function' ||
      typeof partnerUid !== 'string' || !ID.test(partnerUid) ||
      !Number.isSafeInteger(now) || now < 0) {
    return {ok: false, reason: 'invalid_argument'};
  }
  // No production state write in compatibility mode. Existing GO ONLINE flow
  // must continue unchanged until an explicit, coordinated rollout.
  if (enforcementEnabled !== true) return {ok: false, reason: 'enforcement_inactive'};
  const profileRef = db.collection('profiles').doc(partnerUid);
  const verificationRef = db.collection('partnerVerifications').doc(partnerUid);
  const onlineRef = db.collection('partnerOnlineAuthorizations').doc(partnerUid);
  try {
    return await db.runTransaction(async tx => {
      const [profile, verification] = await Promise.all([
        tx.get(profileRef), tx.get(verificationRef)
      ]);
      if (!profile.exists || profile.get('role') !== 'driver' ||
          !verification.exists || verification.get('status') !== 'approved') {
        return {ok: false, reason: 'verification_required'};
      }
      const ids = verification.get('evidenceIds');
      if (!Array.isArray(ids) || ids.length < 2 || ids.length > 10 ||
          !ids.every(id => typeof id === 'string' && ID.test(id)) ||
          new Set(ids).size !== ids.length) {
        return {ok: false, reason: 'evidence_recheck_required'};
      }
      const docs = await Promise.all(ids.map(id =>
        tx.get(db.collection('partnerReviewEvidence').doc(id))));
      const types = new Set();
      let expiresAtMs = Number.MAX_SAFE_INTEGER;
      for (const doc of docs) {
        if (!validatePartnerEvidence(doc, {partnerUid, now})) {
          return {ok: false, reason: 'evidence_invalid'};
        }
        types.add(doc.get('documentType'));
        expiresAtMs = Math.min(expiresAtMs, doc.get('expiresAtMs'));
      }
      if (!types.has('registration_certificate') || !types.has('driving_licence')) {
        return {ok: false, reason: 'documents_incomplete'};
      }
      const reviewRevision = verification.get('reviewRevision');
      if (!Number.isSafeInteger(reviewRevision) || reviewRevision < 0) {
        return {ok: false, reason: 'invalid_review_revision'};
      }
      // A separate server-owned authorization record, not the live driver's
      // presence flag. All reads complete before this write.
      tx.set(onlineRef, {
        authorized: true, authorizedAtMs: now,
        reviewRevision, expiresAtMs,
        evidenceIds: ids
      });
      return {ok: true, reason: 'verified_documents'};
    });
  } catch (_) {
    return {ok: false, reason: 'verification_unavailable'};
  }
}

module.exports = {authorizePartnerOnlineTransaction};
