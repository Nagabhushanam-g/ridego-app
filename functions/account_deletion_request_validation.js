'use strict';

// Preparation-only: validates a deletion request without deleting accounts or
// data. The caller must supply the authenticated Firebase Auth UID.
const ID = /^[A-Za-z0-9_-]{1,128}$/;
const REASONS = new Set(['no_longer_needed', 'privacy', 'other']);

function validateAccountDeletionRequest({authUid, targetUid, reason, activeRide}) {
  if (typeof authUid !== 'string' || !ID.test(authUid)) {
    return {ok: false, reason: 'unauthenticated'};
  }
  if (typeof targetUid !== 'string' || !ID.test(targetUid) || targetUid !== authUid) {
    return {ok: false, reason: 'permission_denied'};
  }
  if (!REASONS.has(reason)) {
    return {ok: false, reason: 'invalid_reason'};
  }
  if (activeRide !== false && activeRide !== true) {
    return {ok: false, reason: 'invalid_active_ride_state'};
  }
  if (activeRide) {
    return {ok: false, reason: 'active_ride'};
  }
  return {ok: true, reason: 'request_eligible'};
}

module.exports = {validateAccountDeletionRequest};
