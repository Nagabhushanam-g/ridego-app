'use strict';

// Inactive policy for a future trusted server-side GO ONLINE gate.
// Never use client-supplied verification status. Rollout defaults to legacy
// compatibility until the migration and backfill are explicitly authorized.
const ID = /^[A-Za-z0-9_-]{1,128}$/;

function evaluatePartnerOnlineEligibility({partnerUid, profile, verification, enforcementEnabled = false}) {
  if (typeof partnerUid !== 'string' || !ID.test(partnerUid) ||
      !profile || !profile.exists || profile.get('role') !== 'driver' ||
      profile.id !== partnerUid) {
    return {allowed: false, reason: 'invalid_partner'};
  }
  if (enforcementEnabled !== true) {
    return {allowed: true, reason: 'legacy_rollout'};
  }
  if (!verification || !verification.exists ||
      verification.id !== partnerUid ||
      verification.get('status') !== 'approved') {
    return {allowed: false, reason: 'verification_required'};
  }
  const ids = verification.get('evidenceIds');
  if (!Array.isArray(ids) || ids.length < 2 || ids.length > 10 ||
      !ids.every(id => typeof id === 'string' && ID.test(id)) ||
      new Set(ids).size !== ids.length) {
    return {allowed: false, reason: 'evidence_recheck_required'};
  }
  // Status alone cannot establish validity: an authorized server must recheck
  // the underlying attestations before allowing an enforced online transition.
  return {allowed: false, reason: 'evidence_recheck_required'};
}

module.exports = {evaluatePartnerOnlineEligibility};
