'use strict';

// Preparation-only Firestore transaction helper. Not an exposed Cloud Function.
// Caller must supply a trusted server-side partner UID and a session document
// reference resolved from a separately validated, opaque session identifier.
// The transaction must commit BEFORE any authorization-code exchange begins.
const { validateAuthorizationCallback } = require('./digilocker_state');

async function consumeAuthorizationSession({ db, sessionRef, state, uid, now = Date.now() }) {
  if (!db || typeof db.runTransaction !== 'function' || !sessionRef ||
      typeof uid !== 'string' || !uid) {
    throw new Error('Invalid authorization session request');
  }
  return db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(sessionRef);
    if (!snapshot.exists) return false;
    const session = snapshot.data();
    if (!validateAuthorizationCallback({ state, session, uid, now })) return false;
    transaction.update(sessionRef, { consumed: true, consumedAtMs: now });
    return true;
  });
}

module.exports = { consumeAuthorizationSession };
