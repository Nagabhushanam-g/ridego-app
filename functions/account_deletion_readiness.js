'use strict';

// Preparation only. This does not delete data or approve a deletion.
// Rechecks blockers at processing time rather than trusting request-time checks.
async function assessAccountDeletionReadiness({db, uid}) {
  if (!db || typeof db.collection !== 'function' ||
      typeof uid !== 'string' || !/^[A-Za-z0-9_-]{1,128}$/.test(uid)) {
    return {ready: false, reason: 'invalid_argument'};
  }
  try {
    const requestRef = db.collection('accountDeletionRequests').doc(uid);
    const driverRides = db.collection('rideRequests').where('driverId', '==', uid)
      .where('status', 'in', ['accepted', 'arrived', 'started']).limit(1);
    const riderRides = db.collection('rideRequests').where('riderId', '==', uid)
      .where('status', 'in', ['requested', 'accepted', 'arrived', 'started']).limit(1);
    const [request, driver, rider] = await Promise.all([
      requestRef.get(), driverRides.get(), riderRides.get()
    ]);
    if (!request.exists || request.get('uid') !== uid ||
        request.get('status') !== 'pending_review') {
      return {ready: false, reason: 'request_not_pending'};
    }
    if (!driver.empty || !rider.empty) {
      return {ready: false, reason: 'active_ride'};
    }
    // Financial and statutory retention decisions have not been approved.
    // Never return a deletion approval until that policy is implemented.
    return {ready: false, reason: 'retention_review_required',
      activeRideClear: true};
  } catch (_) {
    return {ready: false, reason: 'assessment_unavailable'};
  }
}

module.exports = {assessAccountDeletionReadiness};
