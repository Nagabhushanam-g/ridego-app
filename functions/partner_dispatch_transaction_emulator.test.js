'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {initializeApp, getApps} = require('firebase-admin/app');
const {getFirestore} = require('firebase-admin/firestore');
const {authorizePartnerDispatchTransaction} = require('./partner_dispatch_transaction');

if (!process.env.FIRESTORE_EMULATOR_HOST) throw Error('Firestore Emulator required');
if (!getApps().length) initializeApp({projectId: 'ridego-partner-review-test'});
const db = getFirestore('firestore-db-2');
const now = Date.now();
const suffix = now.toString(36) + '-dispatch';
const partnerUid = 'partner-' + suffix;
const rideId = 'ride-' + suffix;
const ids = ['rc-' + suffix, 'dl-' + suffix];

async function seed() {
  await db.collection('profiles').doc(partnerUid).set({role: 'driver'});
  await db.collection('partnerVerifications').doc(partnerUid).set({
    status: 'approved', reviewRevision: 1, evidenceIds: ids
  });
  await db.collection('partnerOnlineAuthorizations').doc(partnerUid).set({
    authorized: true, reviewRevision: 1, evidenceIds: ids, expiresAtMs: now + 60000
  });
  for (const [i, documentType] of ['registration_certificate', 'driving_licence'].entries()) {
    await db.collection('partnerReviewEvidence').doc(ids[i]).set({
      partnerUid, documentType, verified: true, revoked: false,
      source: 'digilocker', issuer: 'trusted-service', sourceReference: 'ref-123',
      verifiedAtMs: now - 1000, expiresAtMs: now + 60000
    });
  }
  await db.collection('rideRequests').doc(rideId).set({
    status: 'requested', driverId: null, riderId: 'rider-test'
  });
}

test('inactive dispatch leaves requested ride untouched', async () => {
  await seed();
  assert.deepEqual(await authorizePartnerDispatchTransaction({
    db, partnerUid, rideId, now
  }), {ok: false, reason: 'enforcement_inactive'});
  assert.equal((await db.collection('rideRequests').doc(rideId).get()).get('status'), 'requested');
});

test('revoked evidence prevents dispatch without changing ride', async () => {
  await db.collection('partnerReviewEvidence').doc(ids[1]).update({revoked: true});
  const result = await authorizePartnerDispatchTransaction({
    db, partnerUid, rideId, now, enforcementEnabled: true
  });
  assert.equal(result.ok, false);
  assert.equal((await db.collection('rideRequests').doc(rideId).get()).get('status'), 'requested');
  await db.collection('partnerReviewEvidence').doc(ids[1]).update({revoked: false});
});

test('concurrent dispatch attempts accept only one ride', async () => {
  const results = await Promise.all(Array.from({length: 3}, () =>
    authorizePartnerDispatchTransaction({
      db, partnerUid, rideId, now, enforcementEnabled: true
    })));
  assert.equal(results.filter(x => x.ok).length, 1);
  const ride = await db.collection('rideRequests').doc(rideId).get();
  assert.equal(ride.get('status'), 'accepted');
  assert.equal(ride.get('driverId'), partnerUid);
});

test('expired grant blocks a new requested ride', async () => {
  const secondRideId = rideId + '-expired';
  await db.collection('rideRequests').doc(secondRideId).set({
    status: 'requested', driverId: null
  });
  await db.collection('partnerOnlineAuthorizations').doc(partnerUid).update({
    expiresAtMs: now
  });
  assert.equal((await authorizePartnerDispatchTransaction({
    db, partnerUid, rideId: secondRideId, now, enforcementEnabled: true
  })).ok, false);
  assert.equal((await db.collection('rideRequests').doc(secondRideId).get()).get('status'), 'requested');
});


test('document expiry at exact dispatch time denies assignment', async () => {
  const target = rideId + '-document-expiry';
  await db.collection('rideRequests').doc(target).set({status: 'requested', driverId: null});
  await db.collection('partnerOnlineAuthorizations').doc(partnerUid).update({
    expiresAtMs: now + 60000
  });
  await db.collection('partnerReviewEvidence').doc(ids[1]).update({
    expiresAtMs: now
  });
  const result = await authorizePartnerDispatchTransaction({
    db, partnerUid, rideId: target, now, enforcementEnabled: true
  });
  assert.equal(result.ok, false);
  assert.equal((await db.collection('rideRequests').doc(target).get()).get('status'), 'requested');
  await db.collection('partnerReviewEvidence').doc(ids[1]).update({
    expiresAtMs: now + 60000
  });
});

test('review revision change prevents dispatch with an old authorization', async () => {
  const target = rideId + '-stale-revision';
  await db.collection('rideRequests').doc(target).set({status: 'requested', driverId: null});
  await db.collection('partnerVerifications').doc(partnerUid).update({reviewRevision: 2});
  const result = await authorizePartnerDispatchTransaction({
    db, partnerUid, rideId: target, now, enforcementEnabled: true
  });
  assert.equal(result.ok, false);
  assert.equal((await db.collection('rideRequests').doc(target).get()).get('status'), 'requested');
  await db.collection('partnerVerifications').doc(partnerUid).update({reviewRevision: 1});
});

test('unapproved Partner cannot dispatch even with a previously valid grant', async () => {
  const target = rideId + '-needs-review';
  await db.collection('rideRequests').doc(target).set({status: 'requested', driverId: null});
  await db.collection('partnerVerifications').doc(partnerUid).update({status: 'needs_review'});
  const result = await authorizePartnerDispatchTransaction({
    db, partnerUid, rideId: target, now, enforcementEnabled: true
  });
  assert.equal(result.ok, false);
  assert.equal((await db.collection('rideRequests').doc(target).get()).get('status'), 'requested');
  await db.collection('partnerVerifications').doc(partnerUid).update({status: 'approved'});
});


test('two different rides cannot be assigned to the same Partner concurrently', async () => {
  const partner = 'partner-' + Date.now().toString(36) + '-parallel';
  const documents = ['rc-' + partner, 'dl-' + partner];
  const rideIds = ['first-' + partner, 'second-' + partner];
  await db.collection('profiles').doc(partner).set({role: 'driver'});
  await db.collection('partnerVerifications').doc(partner).set({
    status: 'approved', reviewRevision: 1, evidenceIds: documents
  });
  await db.collection('partnerOnlineAuthorizations').doc(partner).set({
    authorized: true, reviewRevision: 1, evidenceIds: documents,
    expiresAtMs: now + 60000
  });
  for (const [i, documentType] of ['registration_certificate', 'driving_licence'].entries()) {
    await db.collection('partnerReviewEvidence').doc(documents[i]).set({
      partnerUid: partner, documentType, verified: true, revoked: false,
      source: 'digilocker', issuer: 'trusted-service', sourceReference: 'ref-123',
      verifiedAtMs: now - 1000, expiresAtMs: now + 60000
    });
  }
  for (const id of rideIds) {
    await db.collection('rideRequests').doc(id).set({
      status: 'requested', driverId: null, riderId: 'rider-test'
    });
  }
  const results = await Promise.all(rideIds.map(id =>
    authorizePartnerDispatchTransaction({
      db, partnerUid: partner, rideId: id, now, enforcementEnabled: true
    })));
  assert.equal(results.filter(x => x.ok).length, 1);
  const rides = await Promise.all(rideIds.map(id => db.collection('rideRequests').doc(id).get()));
  assert.equal(rides.filter(x => x.get('status') === 'accepted').length, 1);
  const lock = await db.collection('partnerActiveRideLocks').doc(partner).get();
  assert.equal(lock.exists, true);
  assert.equal(lock.get('rideId'), rides.find(x => x.get('status') === 'accepted').id);
});
