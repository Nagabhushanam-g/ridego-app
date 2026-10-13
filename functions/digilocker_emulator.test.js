'use strict';

// Runs only against Firebase Firestore Emulator. Never connects to production.
// FIRESTORE_EMULATOR_HOST must be set by firebase emulators:exec.
const test = require('node:test');
const assert = require('node:assert/strict');
const { initializeApp, getApps } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { persistAuthorizationSession } = require('./digilocker_session_store');
const { consumeAuthorizationSession } = require('./digilocker_session');

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  throw new Error('Firestore Emulator is required for DigiLocker transaction tests');
}
if (!getApps().length) initializeApp({ projectId: 'ridego-digilocker-security-test' });
const db = getFirestore('firestore-db-2');

test('Firestore transaction accepts only one concurrent callback', async () => {
  const uid = 'test-partner-concurrent';
  const { state, sessionId } = await persistAuthorizationSession({
    db, uid, documentType: 'dl', now: Date.now(),
  });
  const ref = db.collection('digilockerAuthorizationSessions').doc(sessionId);
  const attempts = await Promise.all(Array.from({ length: 8 }, () =>
    consumeAuthorizationSession({ db, sessionRef: ref, state, uid })
  ));
  assert.equal(attempts.filter(Boolean).length, 1);
  const stored = await ref.get();
  assert.equal(stored.get('consumed'), true);
});

test('Firestore transaction rejects wrong owner and expired state', async () => {
  const uid = 'test-partner-owner';
  const now = Date.now();
  const { state, sessionId } = await persistAuthorizationSession({
    db, uid, documentType: 'rc', now,
  });
  const ref = db.collection('digilockerAuthorizationSessions').doc(sessionId);
  assert.equal(await consumeAuthorizationSession({
    db, sessionRef: ref, state, uid: 'other-partner', now: now + 1,
  }), false);
  assert.equal(await consumeAuthorizationSession({
    db, sessionRef: ref, state, uid, now: now + 600000,
  }), false);
  assert.equal((await ref.get()).get('consumed'), false);
});
