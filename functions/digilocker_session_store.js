'use strict';

// Preparation-only persistence helper. Call only from a trusted authenticated
// backend after verifying the caller is an eligible Partner.
// Collection must remain server-only in Firestore security rules.
// Never store raw OAuth state, authorization codes or provider tokens.
const { createAuthorizationSession } = require('./digilocker_session_create');

async function persistAuthorizationSession({ db, uid, documentType, now = Date.now() }) {
  if (!db || typeof db.collection !== 'function') {
    throw new Error('Firestore instance required');
  }
  const { state, sessionId, record } = createAuthorizationSession({
    uid, documentType, now,
  });
  await db.collection('digilockerAuthorizationSessions').doc(sessionId).create(record);
  return { state, sessionId, expiresAtMs: record.expiresAtMs };
}

module.exports = { persistAuthorizationSession };
