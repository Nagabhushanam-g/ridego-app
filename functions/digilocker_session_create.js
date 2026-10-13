'use strict';

// Preparation-only session creation helper. No live endpoints or DigiLocker calls.
// Caller must verify Firebase Auth and driver profile on the trusted backend.
// Never expose stateHash, session document IDs or secret configuration in logs.
const crypto = require('node:crypto');
const { STATE_TTL_MS, newAuthorizationState, hashAuthorizationState } = require('./digilocker_state');

function createAuthorizationSession({ uid, documentType, now = Date.now() }) {
  if (typeof uid !== 'string' || !/^[A-Za-z0-9_-]{1,128}$/.test(uid)) {
    throw new Error('Invalid partner UID');
  }
  if (!['rc', 'dl'].includes(documentType)) {
    throw new Error('Unsupported document type');
  }
  if (!Number.isSafeInteger(now) || now < 0) {
    throw new Error('Invalid creation time');
  }
  const state = newAuthorizationState();
  const sessionId = crypto.randomBytes(24).toString('base64url');
  return {
    state,
    sessionId,
    record: {
      uid,
      documentType,
      stateHash: hashAuthorizationState(state),
      createdAtMs: now,
      expiresAtMs: now + STATE_TTL_MS,
      consumed: false,
    },
  };
}

module.exports = { createAuthorizationSession };
