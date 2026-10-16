'use strict';

// Inactive preparation for server-owned ride assignment. Never exported from
// functions/index.js. Does not change the live client-side acceptance flow.
const {validatePartnerEvidence} = require('./partner_review_evidence');
const ID = /^[A-Za-z0-9_-]{1,128}$/;

async function authorizePartnerDispatchTransaction({
  db, partnerUid, rideId, now = Date.now(), enforcementEnabled = false
}) {
  if (!db || typeof db.runTransaction !== 'function' ||
      typeof partnerUid !== 'string' || !ID.test(partnerUid) ||
      typeof rideId !== 'string' || !ID.test(rideId) ||
      !Number.isSafeInteger(now) || now < 0) {
    return {ok: false, reason: 'invalid_argument'};
  }
  if (enforcementEnabled !== true) return {ok: false, reason: 'enforcement_inactive'};
  try {
    return await db.runTransaction(async tx => {
      const rideRef = db.collection('rideRequests').doc(rideId);
      const profileRef = db.collection('profiles').doc(partnerUid);
      const verificationRef = db.collection('partnerVerifications').doc(partnerUid);
      const grantRef = db.collection('partnerOnlineAuthorizations').doc(partnerUid);
      const activeRideRef = db.collection('partnerActiveRideLocks').doc(partnerUid);
      const [ride, profile, verification, grant, activeRide] = await Promise.all([
        tx.get(rideRef), tx.get(profileRef), tx.get(verificationRef),
        tx.get(grantRef), tx.get(activeRideRef)
      ]);
      if (!ride.exists || ride.get('status') !== 'requested' ||
          ride.get('driverId') != null) {
        return {ok: false, reason: 'ride_unavailable'};
      }
      // A separate lock prevents simultaneous acceptance of different rides.
      // Future activation also requires an authenticated lifecycle release path.
      if (activeRide.exists) {
        return {ok: false, reason: 'partner_already_assigned'};
      }
      if (!profile.exists || profile.get('role') !== 'driver' ||
          !verification.exists || verification.get('status') !== 'approved') {
        return {ok: false, reason: 'verification_required'};
      }
      if (!grant.exists || grant.get('authorized') !== true ||
          !Number.isSafeInteger(grant.get('expiresAtMs')) ||
          grant.get('expiresAtMs') <= now) {
        return {ok: false, reason: 'authorization_required'};
      }
      const revision = verification.get('reviewRevision');
      const ids = verification.get('evidenceIds');
      const grantIds = grant.get('evidenceIds');
      if (!Number.isSafeInteger(revision) || revision < 0 ||
          grant.get('reviewRevision') !== revision ||
          !Array.isArray(ids) || ids.length < 2 || ids.length > 10 ||
          !ids.every(id => typeof id === 'string' && ID.test(id)) ||
          new Set(ids).size !== ids.length ||
          !Array.isArray(grantIds) || grantIds.length !== ids.length ||
          !ids.every((id, index) => grantIds[index] === id)) {
        return {ok: false, reason: 'stale_authorization'};
      }
      const evidence = await Promise.all(ids.map(id =>
        tx.get(db.collection('partnerReviewEvidence').doc(id))));
      const types = new Set();
      let earliestExpiry = Number.MAX_SAFE_INTEGER;
      for (const doc of evidence) {
        if (!validatePartnerEvidence(doc, {partnerUid, now})) {
          return {ok: false, reason: 'evidence_invalid'};
        }
        types.add(doc.get('documentType'));
        earliestExpiry = Math.min(earliestExpiry, doc.get('expiresAtMs'));
      }
      if (!types.has('registration_certificate') || !types.has('driving_licence') ||
          grant.get('expiresAtMs') > earliestExpiry) {
        return {ok: false, reason: 'documents_incomplete'};
      }
      // All validation reads and the assignment write share one transaction.
      // This does not yet check heartbeat presence or duplicate active rides.
      tx.create(activeRideRef, {rideId, partnerUid, assignedAtMs: now});
      tx.update(rideRef, {
        status: 'accepted', driverId: partnerUid, acceptedAt: new Date(now)
      });
      return {ok: true, reason: 'ride_accepted'};
    });
  } catch (_) {
    return {ok: false, reason: 'dispatch_unavailable'};
  }
}

module.exports = {authorizePartnerDispatchTransaction};
