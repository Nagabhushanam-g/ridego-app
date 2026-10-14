'use strict';

// Real Firestore Emulator checks for bounded expiration cleanup.
// No scheduler or production cleanup is enabled by this test.
const test = require('node:test');
const assert = require('node:assert/strict');
const { initializeApp, getApps } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { persistAuthorizationSession } = require('./digilocker_session_store');
const { deleteExpiredAuthorizationSessions } = require('./digilocker_cleanup');

if (!process.env.FIRESTORE_EMULATOR_HOST) throw new Error('Firestore Emulator required');
if (!getApps().length) initializeApp({ projectId: 'ridego-digilocker-security-test' });
const db = getFirestore('firestore-db-2');

test('cleanup removes expired sessions in bounded batches but preserves fresh sessions', async () => {
  // Use an old test clock so parallel Emulator tests with current-time
  // sessions cannot be accidentally deleted by this global cleanup query.
  const clock = 2000000;
  const uid = 'cleanup-partner-' + Date.now();
  const old1 = await persistAuthorizationSession({ db, uid, documentType: 'dl', now: clock - 700000 });
  const old2 = await persistAuthorizationSession({ db, uid, documentType: 'rc', now: clock - 650000 });
  const fresh = await persistAuthorizationSession({ db, uid, documentType: 'dl', now: clock - 1000 });
  try {
    assert.equal(await deleteExpiredAuthorizationSessions({ db, now: clock, limit: 1 }), 1);
    const oldDocs = await Promise.all([old1, old2].map(s =>
      db.collection('digilockerAuthorizationSessions').doc(s.sessionId).get()));
    assert.equal(oldDocs.filter(d => d.exists).length, 1);
    assert.equal((await db.collection('digilockerAuthorizationSessions').doc(fresh.sessionId).get()).exists, true);
    assert.equal(await deleteExpiredAuthorizationSessions({ db, now: clock, limit: 10 }), 1);
    assert.equal((await db.collection('digilockerAuthorizationSessions').doc(fresh.sessionId).get()).exists, true);
  } finally {
    await Promise.all([old1, old2, fresh].map(s =>
      db.collection('digilockerAuthorizationSessions').doc(s.sessionId).delete()));
  }
});
