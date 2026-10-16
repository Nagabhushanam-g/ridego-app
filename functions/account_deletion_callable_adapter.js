'use strict';

// Preparation only: not exported from functions/index.js, not a deployed endpoint.
// Queues a review request; it never deletes Firebase Auth or user data.
const {createAccountDeletionRequest} = require('./account_deletion_request_transaction');

const ERRORS = Object.freeze({
  unauthenticated: 'unauthenticated',
  permission_denied: 'permission-denied',
  invalid_reason: 'invalid-argument',
  invalid_argument: 'invalid-argument',
  active_ride: 'failed-precondition',
  request_unavailable: 'unavailable'
});

async function handleAccountDeletionCallable({request, db, now = Date.now()}) {
  const uid = request?.auth?.uid;
  if (typeof uid !== 'string' || !/^[A-Za-z0-9_-]{1,128}$/.test(uid)) {
    return {ok: false, errorCode: 'unauthenticated'};
  }
  if (!db || typeof db.runTransaction !== 'function') {
    return {ok: false, errorCode: 'unavailable'};
  }
  const data = request?.data;
  if (!data || typeof data !== 'object' || Array.isArray(data) ||
      Object.keys(data).some(key => !['reason', 'targetUid'].includes(key))) {
    return {ok: false, errorCode: 'invalid-argument'};
  }
  // Do not accept client-controlled identity; reject mismatches explicitly.
  if (data.targetUid !== undefined && data.targetUid !== uid) {
    return {ok: false, errorCode: 'permission-denied'};
  }
  try {
    const result = await createAccountDeletionRequest({
      db, authUid: uid, targetUid: uid, reason: data.reason, now
    });
    if (!result.ok) {
      return {ok: false, errorCode: ERRORS[result.reason] || 'internal'};
    }
    // No stored data, internal state or Firestore exception text is returned.
    return {ok: true, status: result.reason === 'already_requested'
      ? 'already_requested' : 'pending_review'};
  } catch (_) {
    return {ok: false, errorCode: 'unavailable'};
  }
}

module.exports = {handleAccountDeletionCallable};
