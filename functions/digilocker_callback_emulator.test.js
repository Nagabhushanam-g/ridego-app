'use strict';

// Firestore Emulator-only OAuth callback integration tests.
// Never connects to production or any real DigiLocker service.
const test = require('node:test');
const assert = require('node:assert/strict');
const { initializeApp, getApps } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { persistAuthorizationSession } = require('./digilocker_session_store');
const { processResolvedDigiLockerCallback } = require('./digilocker_resolved_callback');

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  throw new Error('Firestore Emulator required for callback integration tests');
}
if (!getApps().length) initializeApp({ projectId: 'ridego-digilocker-security-test' });
const db = getFirestore('firestore-db-2');

test('concurrent callbacks resolve hashed state and consume session only once', async () => {
  const now = Date.now();
  const uid = 'callback-partner-' + now;
  const { state, sessionId } = await persistAuthorizationSession({
    db, uid, documentType: 'dl', now,
  });
  const attempts = await Promise.all(Array.from({ length: 8 }, () =>
    processResolvedDigiLockerCallback({
      db, query: { state, code: 'test-only-code', uid: 'attacker-uid' },
      now: now + 1000,
    })
  ));
  assert.equal(attempts.filter(result => result.ok).length, 1);
  assert.equal(attempts.filter(result => !result.ok).length, 7);
  const stored = await db.collection('digilockerAuthorizationSessions').doc(sessionId).get();
  assert.equal(stored.get('uid'), uid);
  assert.equal(stored.get('consumed'), true);
  assert.equal(stored.get('state'), undefined);
});

test('callback denies unknown state without consuming other sessions', async () => {
  const now = Date.now();
  const { state, sessionId } = await persistAuthorizationSession({
    db, uid: 'callback-missing-' + now, documentType: 'rc', now,
  });
  const otherState = state[0] === 'A' ? 'B' + state.slice(1) : 'A' + state.slice(1);
  assert.deepEqual(await processResolvedDigiLockerCallback({
    db, query: { state: otherState, code: 'test-only-code' }, now: now + 1000,
  }), { ok: false, reason: 'invalid_or_expired_session' });
  const stored = await db.collection('digilockerAuthorizationSessions').doc(sessionId).get();
  assert.equal(stored.get('consumed'), false);
});

test('denied callback consumes state and cannot be replayed', async () => {
  const now = Date.now();
  const { state } = await persistAuthorizationSession({
    db, uid: 'callback-denied-' + now, documentType: 'dl', now,
  });
  assert.deepEqual(await processResolvedDigiLockerCallback({
    db, query: { state, error: 'access_denied' }, now: now + 1000,
  }), { ok: true, outcome: 'denied' });
  assert.deepEqual(await processResolvedDigiLockerCallback({
    db, query: { state, code: 'test-only-code' }, now: now + 2000,
  }), { ok: false, reason: 'invalid_or_expired_session' });
});
