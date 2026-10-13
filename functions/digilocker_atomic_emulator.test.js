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
