'use strict';

// Preparation only. Server-side callers must evaluate this at the time of use.
// Authorization records are not proof of current document validity.
const {validatePartnerEvidence} = require('./partner_review_evidence');
const ID = /^[A-Za-z0-9_-]{1,128}$/;

async function checkPartnerOnlineGrant({db, partnerUid, now = Date.now()}) {
  if (!db || typeof db.collection !== 'function' ||
      typeof partnerUid !== 'string' || !ID.test(partnerUid) ||
      !Number.isSafeInteger(now) || now < 0) {
    return {allowed: false, reason: 'invalid_argument'};
  }
  try {
    const [grant, verification] = await Promise.all([
      db.collection('partnerOnlineAuthorizations').doc(partnerUid).get(),
      db.collection('partnerVerifications').doc(partnerUid).get()
    ]);
    if (!grant.exists || grant.get('authorized') !== true) {
      return {allowed: false, reason: 'authorization_required'};
    }
    if (!Number.isSafeInteger(grant.get('expiresAtMs')) ||
        grant.get('expiresAtMs') <= now) {
      return {allowed: false, reason: 'authorization_expired'};
    }
    if (!verification.exists || verification.get('status') !== 'approved') {
      return {allowed: false, reason: 'verification_required'};
    }
    const revision = verification.get('reviewRevision');
    if (!Number.isSafeInteger(revision) || revision < 0 ||
        grant.get('reviewRevision') !== revision) {
      return {allowed: false, reason: 'stale_authorization'};
    }
    const ids = verification.get('evidenceIds');
    const grantIds = grant.get('evidenceIds');
    if (!Array.isArray(ids) || ids.length < 2 || ids.length > 10 ||
        !ids.every(id => typeof id === 'string' && ID.test(id)) ||
        new Set(ids).size !== ids.length ||
        !Array.isArray(grantIds) || grantIds.length !== ids.length ||
        !ids.every((id, index) => grantIds[index] === id)) {
      return {allowed: false, reason: 'stale_authorization'};
    }
    const docs = await Promise.all(ids.map(id =>
      db.collection('partnerReviewEvidence').doc(id).get()));
    const types = new Set();
    let earliestExpiry = Number.MAX_SAFE_INTEGER;
    for (const doc of docs) {
      if (!validatePartnerEvidence(doc, {partnerUid, now})) {
        return {allowed: false, reason: 'evidence_invalid'};
      }
      types.add(doc.get('documentType'));
      earliestExpiry = Math.min(earliestExpiry, doc.get('expiresAtMs'));
    }
    if (!types.has('registration_certificate') || !types.has('driving_licence')) {
      return {allowed: false, reason: 'documents_incomplete'};
    }
    if (grant.get('expiresAtMs') > earliestExpiry) {
      return {allowed: false, reason: 'stale_authorization'};
    }
    return {allowed: true, reason: 'verified_documents'};
  } catch (_) {
    return {allowed: false, reason: 'verification_unavailable'};
  }
}

module.exports = {checkPartnerOnlineGrant};
