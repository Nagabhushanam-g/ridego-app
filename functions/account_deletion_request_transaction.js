'use strict';

// Preparation-only. This queues a review request, NEVER deletes an account.
// Not exported from functions/index.js or deployed as a callable.
const {validateAccountDeletionRequest} = require('./account_deletion_request_validation');
const ID = /^[A-Za-z0-9_-]{1,128}$/;

async function createAccountDeletionRequest({db, authUid, targetUid, reason, now = Date.now()}) {
  if (!db || typeof db.runTransaction !== 'function' ||
      !Number.isSafeInteger(now) || now < 0) {
    return {ok: false, reason: 'invalid_argument'};
  }
  // Check identity and reason before any database access.
  const input = validateAccountDeletionRequest({authUid, targetUid, reason, activeRide: false});
  if (!input.ok) return input;
  if (!ID.test(targetUid)) return {ok: false, reason: 'permission_denied'};
  try {
    return await db.runTransaction(async tx => {
      const requestRef = db.collection('accountDeletionRequests').doc(targetUid);
      const activeQuery = db.collection('rideRequests').where('driverId', '==', targetUid)
        .where('status', 'in', ['accepted', 'arrived', 'started']).limit(1);
      const riderQuery = db.collection('rideRequests').where('riderId', '==', targetUid)
        .where('status', 'in', ['requested', 'accepted', 'arrived', 'started']).limit(1);
      const [existing, driverRides, riderRides] = await Promise.all([
        tx.get(requestRef), tx.get(activeQuery), tx.get(riderQuery)
      ]);
      if (!driverRides.empty || !riderRides.empty) return {ok: false, reason: 'active_ride'};
      if (existing.exists) return {ok: true, reason: 'already_requested'};
      tx.create(requestRef, {
        uid: targetUid, reason, status: 'pending_review',
        requestedAtMs: now, source: 'authenticated_request'
      });
      return {ok: true, reason: 'request_created'};
    });
  } catch (_) {
    return {ok: false, reason: 'request_unavailable'};
  }
}

module.exports = {createAccountDeletionRequest};
