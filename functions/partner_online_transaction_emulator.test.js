'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {initializeApp, getApps} = require('firebase-admin/app');
const {getFirestore} = require('firebase-admin/firestore');
const {authorizePartnerOnlineTransaction} = require('./partner_online_transaction');

if (!process.env.FIRESTORE_EMULATOR_HOST) throw new Error('Firestore Emulator required');
if (!getApps().length) initializeApp({projectId: 'ridego-partner-review-test'});
const db = getFirestore('firestore-db-2');

test('inactive enforcement never creates online authorization', async () => {
  const partnerUid = 'inactive-' + Date.now().toString(36);
  assert.deepEqual(await authorizePartnerOnlineTransaction({db, partnerUid}),
    {ok: false, reason: 'enforcement_inactive'});
  assert.equal((await db.collection('partnerOnlineAuthorizations').doc(partnerUid).get()).exists, false);
});

test('atomic online authorization requires valid RC and DL', async () => {
  const suffix = Date.now().toString(36) + '-online';
  const partnerUid = 'partner-' + suffix;
  const now = Date.now();
  const rcId = 'rc-' + suffix;
  const dlId = 'dl-' + suffix;
  const base = {
    partnerUid, verified: true, revoked: false, source: 'digilocker',
    issuer: 'trusted-service', sourceReference: 'ref-123',
    verifiedAtMs: now - 1000, expiresAtMs: now + 86400000
  };
  await db.collection('profiles').doc(partnerUid).set({role: 'driver'});
  await db.collection('partnerVerifications').doc(partnerUid).set({
    status: 'approved', evidenceIds: [rcId, dlId], reviewRevision: 2
  });
  await db.collection('partnerReviewEvidence').doc(rcId).set({
    ...base, documentType: 'registration_certificate'
  });
  await db.collection('partnerReviewEvidence').doc(dlId).set({
    ...base, documentType: 'driving_licence', revoked: true
  });
  assert.equal((await authorizePartnerOnlineTransaction({
    db, partnerUid, now, enforcementEnabled: true
  })).ok, false);
  assert.equal((await db.collection('partnerOnlineAuthorizations').doc(partnerUid).get()).exists, false);
  await db.collection('partnerReviewEvidence').doc(dlId).update({revoked: false});
  assert.deepEqual(await authorizePartnerOnlineTransaction({
    db, partnerUid, now, enforcementEnabled: true
  }), {ok: true, reason: 'verified_documents'});
  const authorization = await db.collection('partnerOnlineAuthorizations').doc(partnerUid).get();
  assert.equal(authorization.get('authorized'), true);
  assert.equal(authorization.get('reviewRevision'), 2);
});

test('missing approval cannot create online authorization', async () => {
  const partnerUid = 'missing-' + Date.now().toString(36);
  const result = await authorizePartnerOnlineTransaction({
    db, partnerUid, now: Date.now(), enforcementEnabled: true
  });
  assert.equal(result.ok, false);
  assert.equal((await db.collection('partnerOnlineAuthorizations').doc(partnerUid).get()).exists, false);
});
