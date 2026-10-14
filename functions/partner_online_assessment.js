'use strict';

// Preparation only: trusted backend may use this read-only assessment before a
// future GO ONLINE write. Not exported from functions/index.js.
const {validatePartnerEvidence} = require('./partner_review_evidence');
const {evaluatePartnerOnlineEligibility} = require('./partner_online_eligibility');
const ID = /^[A-Za-z0-9_-]{1,128}$/;

async function assessPartnerOnlineEligibility({db, partnerUid, now = Date.now(), enforcementEnabled = false}) {
  if (!db || typeof db.collection !== 'function' ||
      typeof partnerUid !== 'string' || !ID.test(partnerUid) ||
      !Number.isSafeInteger(now) || now < 0) {
    return {allowed: false, reason: 'invalid_argument'};
  }
  try {
    const [profile, verification] = await Promise.all([
      db.collection('profiles').doc(partnerUid).get(),
      db.collection('partnerVerifications').doc(partnerUid).get()
    ]);
    const policy = evaluatePartnerOnlineEligibility({
      partnerUid, profile, verification, enforcementEnabled
    });
    if (policy.allowed || enforcementEnabled !== true ||
        policy.reason !== 'evidence_recheck_required') return policy;
    const ids = verification.get('evidenceIds');
    const docs = await Promise.all(ids.map(id =>
      db.collection('partnerReviewEvidence').doc(id).get()));
    const types = new Set();
    for (const doc of docs) {
      if (!validatePartnerEvidence(doc, {partnerUid, now})) {
        return {allowed: false, reason: 'evidence_invalid'};
      }
      types.add(doc.get('documentType'));
    }
    return types.has('registration_certificate') && types.has('driving_licence')
      ? {allowed: true, reason: 'verified_documents'}
      : {allowed: false, reason: 'documents_incomplete'};
  } catch (_) {
    return {allowed: false, reason: 'verification_unavailable'};
  }
}

module.exports = {assessPartnerOnlineEligibility};
