'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {initializeApp, getApps} = require('firebase-admin/app');
const {getFirestore} = require('firebase-admin/firestore');
const {recheckApprovedPartnerEvidence} = require('./partner_review_recheck');

if (!process.env.FIRESTORE_EMULATOR_HOST) throw new Error('Firestore Emulator required');
if (!getApps().length) initializeApp({projectId: 'ridego-partner-review-test'});
const db = getFirestore('firestore-db-2');

test('approved Partner stays approved with valid RC and DL, then moves to review on revocation', async () => {
  const suffix = Date.now().toString(36) + '-recheck';
  const partnerUid = 'partner-' + suffix;
  const rcId = 'rc-' + suffix;
  const dlId = 'dl-' + suffix;
  const now = Date.now();
  const base = {
    partnerUid, verified: true, revoked: false, source: 'digilocker',
    issuer: 'trusted-service', sourceReference: 'ref-123',
    verifiedAtMs: now - 1000, expiresAtMs: now + 86400000
  };
  await db.collection('partnerReviewEvidence').doc(rcId).set({
    ...base, documentType: 'registration_certificate'
  });
  await db.collection('partnerReviewEvidence').doc(dlId).set({
    ...base, documentType: 'driving_licence'
  });
  await db.collection('partnerVerifications').doc(partnerUid).set({
    status: 'approved', reviewRevision: 1, evidenceIds: [rcId, dlId]
  });
  assert.deepEqual(await recheckApprovedPartnerEvidence({db, partnerUid, now}),
    {ok: true, status: 'approved'});
  await db.collection('partnerReviewEvidence').doc(dlId).update({revoked: true});
  const attempts = await Promise.all(Array.from({length: 3}, () =>
    recheckApprovedPartnerEvidence({db, partnerUid, now: now + 1})));
  assert.equal(attempts.filter(x => x.ok && x.status === 'needs_review').length, 1);
  const updated = await db.collection('partnerVerifications').doc(partnerUid).get();
  assert.equal(updated.get('status'), 'needs_review');
  assert.equal(updated.get('reviewRevision'), 2);
  const audit = await db.collection('partnerReviewAudit').where('partnerUid', '==', partnerUid).get();
  assert.equal(audit.size, 1);
  assert.equal(audit.docs[0].get('event'), 'partner_evidence_invalidated');
});

test('expired evidence triggers review and a second recheck cannot duplicate audit', async () => {
  const suffix = Date.now().toString(36) + '-expired';
  const partnerUid = 'partner-' + suffix;
  const rcId = 'rc-' + suffix;
  const dlId = 'dl-' + suffix;
  const now = Date.now();
  const base = {
    partnerUid, verified: true, revoked: false, source: 'digilocker',
    issuer: 'trusted-service', sourceReference: 'ref-123',
    verifiedAtMs: now - 1000, expiresAtMs: now + 86400000
  };
  await db.collection('partnerReviewEvidence').doc(rcId).set({
    ...base, documentType: 'registration_certificate'
  });
  await db.collection('partnerReviewEvidence').doc(dlId).set({
    ...base, documentType: 'driving_licence', expiresAtMs: now
  });
  await db.collection('partnerVerifications').doc(partnerUid).set({
    status: 'approved', reviewRevision: 0, evidenceIds: [rcId, dlId]
  });
  assert.deepEqual(await recheckApprovedPartnerEvidence({db, partnerUid, now}),
    {ok: true, status: 'needs_review'});
  assert.deepEqual(await recheckApprovedPartnerEvidence({db, partnerUid, now}),
    {ok: false, errorCode: 'not-approved'});
  assert.equal((await db.collection('partnerReviewAudit').where('partnerUid', '==', partnerUid).get()).size, 1);
});
