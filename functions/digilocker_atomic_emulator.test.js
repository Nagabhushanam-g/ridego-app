'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { initializeApp, getApps } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { createRateLimitedDigiLockerSession } = require('./digilocker_atomic_session');

if (!process.env.FIRESTORE_EMULATOR_HOST) throw new Error('Firestore Emulator required');
if (!getApps().length) initializeApp({ projectId: 'ridego-digilocker-security-test' });
const db = getFirestore('firestore-db-2');

test('concurrent attempts create exactly one session and one quota reservation', async () => {
  const uid = 'atomic-partner-' + Date.now();
  const now = Date.now();
  const attempts = await Promise.all(Array.from({ length: 5 }, () =>
    createRateLimitedDigiLockerSession({ db, uid, documentType: 'dl', now })
  ));
  assert.equal(attempts.filter(x => x.ok).length, 1);
  const rate = await db.collection('digilockerPartnerRateLimits').doc(uid).get();
  assert.equal(rate.get('count'), 1);
  const sessions = await db.collection('digilockerAuthorizationSessions').where('uid', '==', uid).get();
  assert.equal(sessions.size, 1);
});

test('failed transaction does not consume quota', async () => {
  const uid = 'atomic-failure-' + Date.now();
  const failingDb = {
    collection: (name) => db.collection(name),
    runTransaction: async () => { throw new Error('simulated transaction failure'); },
  };
  await assert.rejects(createRateLimitedDigiLockerSession({
    db: failingDb, uid, documentType: 'rc', now: Date.now(),
  }), /simulated transaction failure/);
  assert.equal((await db.collection('digilockerPartnerRateLimits').doc(uid).get()).exists, false);
});

test('Firestore rolls back session and quota when transaction aborts after writes', async () => {
  const uid = 'atomic-rollback-' + Date.now();
  const abortingDb = {
    collection: (name) => db.collection(name),
    runTransaction: (fn) => db.runTransaction(async (tx) => {
      await fn(tx); // Both writes are queued in the real Firestore transaction.
      throw new Error('forced rollback after writes');
    }),
  };
  await assert.rejects(createRateLimitedDigiLockerSession({
    db: abortingDb, uid, documentType: 'dl', now: Date.now(),
  }), /forced rollback after writes/);
  assert.equal((await db.collection('digilockerPartnerRateLimits').doc(uid).get()).exists, false);
  const sessions = await db.collection('digilockerAuthorizationSessions')
    .where('uid', '==', uid).get();
  assert.equal(sessions.size, 0);
});

test('Firestore enforces hourly quota and resets it after an hour', async () => {
  const uid = 'atomic-hourly-' + Date.now();
  const now = Date.now();
  for (let i = 0; i < 5; i++) {
    const result = await createRateLimitedDigiLockerSession({
      db, uid, documentType: 'rc', now: now + i * 61000,
    });
    assert.equal(result.ok, true);
  }
  const blocked = await createRateLimitedDigiLockerSession({
    db, uid, documentType: 'rc', now: now + 5 * 61000,
  });
  assert.deepEqual(blocked, { ok: false, reason: 'hourly_limit' });
  const reset = await createRateLimitedDigiLockerSession({
    db, uid, documentType: 'rc', now: now + 3600000,
  });
  assert.equal(reset.ok, true);
  assert.equal((await db.collection('digilockerPartnerRateLimits').doc(uid).get()).get('count'), 1);
});
