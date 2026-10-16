'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {initializeApp, getApps} = require('firebase-admin/app');
const {getFirestore} = require('firebase-admin/firestore');
const {releasePartnerActiveRideLock} = require('./partner_active_ride_release');
if (!process.env.FIRESTORE_EMULATOR_HOST) throw Error('Firestore Emulator required');
if (!getApps().length) initializeApp({projectId: 'ridego-partner-review-test'});
const db = getFirestore('firestore-db-2');

test('only terminal matching ride releases its own Partner lock', async () => {
  const suffix = Date.now().toString(36) + '-release';
  const partnerUid = 'partner-' + suffix;
  const rideId = 'ride-' + suffix;
  const otherId = 'other-' + suffix;
  const now = Date.now();
  const rideRef = db.collection('rideRequests').doc(rideId);
  const lockRef = db.collection('partnerActiveRideLocks').doc(partnerUid);
  await rideRef.set({status: 'accepted', driverId: partnerUid});
  await lockRef.set({rideId, partnerUid, assignedAtMs: now});
  assert.deepEqual(await releasePartnerActiveRideLock({db, partnerUid, rideId, now}),
    {ok: false, reason: 'enforcement_inactive'});
  assert.deepEqual(await releasePartnerActiveRideLock({
    db, partnerUid, rideId, now, enforcementEnabled: true
  }), {ok: false, reason: 'ride_not_terminal'});
  assert.deepEqual(await releasePartnerActiveRideLock({
    db, partnerUid, rideId: otherId, now, enforcementEnabled: true
  }), {ok: false, reason: 'lock_mismatch'});
  assert.equal((await lockRef.get()).exists, true);
  await rideRef.update({status: 'completed'});
  const results = await Promise.all(Array.from({length: 3}, () =>
    releasePartnerActiveRideLock({db, partnerUid, rideId, now, enforcementEnabled: true})));
  assert.equal(results.every(r => r.ok), true);
  assert.equal(results.filter(r => r.reason === 'lock_released').length, 1);
  assert.equal((await lockRef.get()).exists, false);
});

test('a terminal ride assigned to another Partner cannot release a lock', async () => {
  const suffix = Date.now().toString(36) + '-mismatch';
  const partnerUid = 'partner-' + suffix;
  const rideId = 'ride-' + suffix;
  await db.collection('rideRequests').doc(rideId).set({
    status: 'completed', driverId: 'another-driver'
  });
  const lockRef = db.collection('partnerActiveRideLocks').doc(partnerUid);
  await lockRef.set({rideId, partnerUid});
  assert.deepEqual(await releasePartnerActiveRideLock({
    db, partnerUid, rideId, enforcementEnabled: true
  }), {ok: false, reason: 'ride_not_terminal'});
  assert.equal((await lockRef.get()).exists, true);
});
