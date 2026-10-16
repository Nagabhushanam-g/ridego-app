'use strict';

// Preparation only. Never exported from functions/index.js.
// A Partner's ride lock may be released only for its exact terminal ride.
const ID = /^[A-Za-z0-9_-]{1,128}$/;
const TERMINAL = new Set(['completed', 'cancelled', 'expired']);

async function releasePartnerActiveRideLock({
  db, partnerUid, rideId, now = Date.now(), enforcementEnabled = false
}) {
  if (!db || typeof db.runTransaction !== 'function' ||
      typeof partnerUid !== 'string' || !ID.test(partnerUid) ||
      typeof rideId !== 'string' || !ID.test(rideId) ||
      !Number.isSafeInteger(now) || now < 0) {
    return {ok: false, reason: 'invalid_argument'};
  }
  if (enforcementEnabled !== true) return {ok: false, reason: 'enforcement_inactive'};
  const rideRef = db.collection('rideRequests').doc(rideId);
  const lockRef = db.collection('partnerActiveRideLocks').doc(partnerUid);
  try {
    return await db.runTransaction(async tx => {
      const [ride, lock] = await Promise.all([tx.get(rideRef), tx.get(lockRef)]);
      if (!lock.exists) return {ok: true, reason: 'already_released'};
      if (lock.get('partnerUid') !== partnerUid || lock.get('rideId') !== rideId) {
        return {ok: false, reason: 'lock_mismatch'};
      }
      if (!ride.exists || ride.get('driverId') !== partnerUid ||
          !TERMINAL.has(ride.get('status'))) {
        return {ok: false, reason: 'ride_not_terminal'};
      }
      tx.delete(lockRef);
      return {ok: true, reason: 'lock_released'};
    });
  } catch (_) {
    return {ok: false, reason: 'release_unavailable'};
  }
}

module.exports = {releasePartnerActiveRideLock};
