'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {initializeApp, getApps} = require('firebase-admin/app');
const {getFirestore} = require('firebase-admin/firestore');
const {createAccountDeletionRequest} = require('./account_deletion_request_transaction');

if (!process.env.FIRESTORE_EMULATOR_HOST) throw new Error('Firestore Emulator required');
if (!getApps().length) initializeApp({projectId: 'ridego-account-deletion-test'});
const db = getFirestore('firestore-db-2');
const suffix = () => Date.now().toString(36) + '-' + Math.random().toString(36).slice(2, 8);
const request = uid => ({db, authUid: uid, targetUid: uid, reason: 'privacy', now: Date.now()});

test('owner can queue once; concurrent retries do not duplicate', async () => {
  const uid = 'owner-' + suffix();
  const results = await Promise.all(Array.from({length: 3}, () =>
    createAccountDeletionRequest(request(uid))));
  assert.equal(results.every(r => r.ok), true, JSON.stringify(results));
  assert.equal(results.filter(r => r.reason === 'request_created').length, 1);
  const snapshot = await db.collection('accountDeletionRequests').doc(uid).get();
  assert.equal(snapshot.get('status'), 'pending_review');
  assert.equal(snapshot.get('uid'), uid);
});

test('cross-account and anonymous requests are denied', async () => {
  const uid = 'victim-' + suffix();
  assert.equal((await createAccountDeletionRequest({
    ...request(uid), authUid: 'attacker'
  })).reason, 'permission_denied');
  assert.equal((await createAccountDeletionRequest({
    ...request(uid), authUid: null
  })).reason, 'unauthenticated');
  assert.equal((await db.collection('accountDeletionRequests').doc(uid).get()).exists, false);
});

test('active driver or rider trip prevents queueing', async () => {
  for (const role of ['driverId', 'riderId']) {
    const uid = 'active-' + suffix();
    const rideId = 'ride-' + suffix();
    await db.collection('rideRequests').doc(rideId).set({
      [role]: uid, status: 'started'
    });
    assert.deepEqual(await createAccountDeletionRequest(request(uid)),
      {ok: false, reason: 'active_ride'});
    assert.equal((await db.collection('accountDeletionRequests').doc(uid).get()).exists, false);
  }
});
