'use strict';

// Server-only OAuth callback session lookup. No public endpoint is exported.
// The callback provides only opaque state; never trust callback-provided UID.
// State is hashed before lookup and the matching record is revalidated in a
// transaction by consumeAuthorizationSession.
const { hashAuthorizationState } = require('./digilocker_state');

async function resolveDigiLockerCallbackSession({ db, state }) {
  if (!db || typeof db.collection !== 'function') {
    throw new Error('Invalid Firestore database');
  }
  let stateHash;
  try { stateHash = hashAuthorizationState(state); }
  catch (_) { return { ok: false, reason: 'invalid_state' }; }

  const matches = await db.collection('digilockerAuthorizationSessions')
    .where('stateHash', '==', stateHash)
    .limit(2)
    .get();
  // Refuse ambiguous matches rather than selecting a potentially wrong owner.
  if (matches.size !== 1) return { ok: false, reason: 'session_not_unique' };
  const doc = matches.docs[0];
  const uid = doc.get('uid');
  if (typeof uid !== 'string' || !/^[A-Za-z0-9_-]{1,128}$/.test(uid)) {
    return { ok: false, reason: 'invalid_owner' };
  }
  return { ok: true, sessionRef: doc.ref, uid };
}

module.exports = { resolveDigiLockerCallbackSession };
