'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {initializeApp, getApps} = require('firebase-admin/app');
const {getFirestore} = require('firebase-admin/firestore');
const {recordPartnerReview} = require('./partner_review_transaction');
const {preparePartnerReviewDecision} = require('./partner_review_policy');

if (!process.env.FIRESTORE_EMULATOR_HOST) throw new Error('Firestore Emulator required');
if (!getApps().length) initializeApp({projectId: 'ridego-partner-review-test'});
const db = getFirestore('firestore-db-2');

test('two simultaneous first reviews create only one verification and audit entry', async () => {
  const suffix = Date.now().toString(36) + '-' + Math.random().toString(36).slice(2, 8);
  const partnerUid = 'partner-' + suffix;
  const reviewers = ['reviewer-a-' + suffix, 'reviewer-b-' + suffix];
  await db.collection('profiles').doc(partnerUid).set({uid: partnerUid, role: 'driver'});
  await Promise.all(reviewers.map(uid =>
    db.collection('partnerReviewers').doc(uid).set({active: true, role: 'partner_reviewer'})
  ));
  const evidenceId = 'rc-' + suffix;
  await db.collection('partnerReviewEvidence').doc(evidenceId).set({
    partnerUid, verified: true, revoked: false, source: 'digilocker', documentType: 'registration_certificate', issuer: 'trusted-service', sourceReference: 'ref-123', verifiedAtMs: Date.now() - 1000, expiresAtMs: Date.now() + 86400000
  });
  const dlEvidenceId = 'dl-' + suffix;
  await db.collection('partnerReviewEvidence').doc(dlEvidenceId).set({
    partnerUid, verified: true, revoked: false, source: 'digilocker',
    documentType: 'driving_licence', issuer: 'trusted-service',
    sourceReference: 'ref-456', verifiedAtMs: Date.now() - 1000,
    expiresAtMs: Date.now() + 86400000
  });
  const now = Date.now();
  const decisions = reviewers.map((reviewerUid, i) =>
    preparePartnerReviewDecision({
      reviewerUid, reviewerAuthorized: true, partnerUid,
      status: i === 0 ? 'approved' : 'rejected',
      reasonCode: i === 0 ? 'verification_complete' : 'document_mismatch',
      now
    })
  );
  const results = await Promise.all(decisions.map(decision =>
    recordPartnerReview({db, decision, evidenceIds: [evidenceId, dlEvidenceId], now})
  ));
  assert.equal(results.filter(x => x.ok).length, 1);
  const verification = await db.collection('partnerVerifications').doc(partnerUid).get();
  assert.equal(verification.exists, true);
  assert.ok(['approved', 'rejected'].includes(verification.get('status')));
  const audit = await db.collection('partnerReviewAudit').where('partnerUid', '==', partnerUid).get();
  assert.equal(audit.size, 1);
  assert.equal(audit.docs[0].get('status'), verification.get('status'));
  assert.equal(audit.docs[0].get('reviewedBy'), verification.get('reviewedBy'));
});

test('inactive reviewer cannot create verification or audit', async () => {
  const suffix = Date.now().toString(36) + '-inactive';
  const partnerUid = 'partner-' + suffix;
  const reviewerUid = 'reviewer-' + suffix;
  await db.collection('profiles').doc(partnerUid).set({uid: partnerUid, role: 'driver'});
  await db.collection('partnerReviewers').doc(reviewerUid).set({active: false, role: 'partner_reviewer'});
  const now = Date.now();
  const decision = preparePartnerReviewDecision({
    reviewerUid, reviewerAuthorized: true, partnerUid,
    status: 'approved', reasonCode: 'verification_complete', now
  });
  const result = await recordPartnerReview({db, decision, evidenceIds: ['missing-evidence'], now});
  assert.equal(result.ok, false);
  assert.equal((await db.collection('partnerVerifications').doc(partnerUid).get()).exists, false);
  assert.equal((await db.collection('partnerReviewAudit').where('partnerUid', '==', partnerUid).get()).size, 0);
});

test('unverified or cross-partner evidence cannot approve or write audit', async () => {
  const suffix = Date.now().toString(36) + '-evidence';
  const partnerUid = 'partner-' + suffix;
  const reviewerUid = 'reviewer-' + suffix;
  await db.collection('profiles').doc(partnerUid).set({uid: partnerUid, role: 'driver'});
  await db.collection('partnerReviewers').doc(reviewerUid).set({active: true, role: 'partner_reviewer'});
  const now = Date.now();
  const decision = preparePartnerReviewDecision({
    reviewerUid, reviewerAuthorized: true, partnerUid,
    status: 'approved', reasonCode: 'verification_complete', now
  });
  for (const [kind, evidence] of [
    ['unverified', {partnerUid, verified: false, revoked: false}],
    ['other-partner', {partnerUid: 'another-partner', verified: true, revoked: false}],
    ['revoked', {partnerUid, verified: true, revoked: true}]
  ]) {
    const evidenceId = kind + '-' + suffix;
    await db.collection('partnerReviewEvidence').doc(evidenceId).set(evidence);
    const result = await recordPartnerReview({db, decision, evidenceIds: [evidenceId], now});
    assert.equal(result.ok, false, kind);
  }
  assert.equal((await db.collection('partnerVerifications').doc(partnerUid).get()).exists, false);
  assert.equal((await db.collection('partnerReviewAudit').where('partnerUid', '==', partnerUid).get()).size, 0);
});

test('existing pending verification is not overwritten by initial-review helper', async () => {
  const suffix = Date.now().toString(36) + '-pending';
  const partnerUid = 'partner-' + suffix;
  const reviewerUid = 'reviewer-' + suffix;
  await db.collection('profiles').doc(partnerUid).set({uid: partnerUid, role: 'driver'});
  await db.collection('partnerReviewers').doc(reviewerUid).set({active: true, role: 'partner_reviewer'});
  await db.collection('partnerVerifications').doc(partnerUid).set({status: 'pending'});
  const evidenceId = 'rc-' + suffix;
  await db.collection('partnerReviewEvidence').doc(evidenceId).set({
    partnerUid, verified: true, revoked: false, source: 'digilocker', documentType: 'registration_certificate', issuer: 'trusted-service', sourceReference: 'ref-123', verifiedAtMs: Date.now() - 1000, expiresAtMs: Date.now() + 86400000
  });
  const now = Date.now();
  const decision = preparePartnerReviewDecision({
    reviewerUid, reviewerAuthorized: true, partnerUid,
    status: 'approved', reasonCode: 'verification_complete', now
  });
  const result = await recordPartnerReview({db, decision, evidenceIds: [evidenceId], now});
  assert.equal(result.ok, false);
  assert.equal((await db.collection('partnerVerifications').doc(partnerUid).get()).get('status'), 'pending');
  assert.equal((await db.collection('partnerReviewAudit').where('partnerUid', '==', partnerUid).get()).size, 0);
});


test('verified RC alone cannot approve Partner in Firestore', async () => {
  const suffix = Date.now().toString(36) + '-rc-only';
  const partnerUid = 'partner-' + suffix;
  const reviewerUid = 'reviewer-' + suffix;
  const now = Date.now();
  await db.collection('profiles').doc(partnerUid).set({role: 'driver'});
  await db.collection('partnerReviewers').doc(reviewerUid).set({active: true, role: 'partner_reviewer'});
  const evidenceId = 'rc-' + suffix;
  await db.collection('partnerReviewEvidence').doc(evidenceId).set({
    partnerUid, verified: true, revoked: false, source: 'digilocker',
    documentType: 'registration_certificate', issuer: 'trusted-service',
    sourceReference: 'ref-123', verifiedAtMs: now - 1000, expiresAtMs: now + 86400000
  });
  const decision = preparePartnerReviewDecision({
    reviewerUid, reviewerAuthorized: true, partnerUid, status: 'approved',
    reasonCode: 'verification_complete', now
  });
  const result = await recordPartnerReview({db, decision, evidenceIds: [evidenceId], now});
  assert.equal(result.ok, false);
  assert.equal((await db.collection('partnerVerifications').doc(partnerUid).get()).exists, false);
  assert.equal((await db.collection('partnerReviewAudit').where('partnerUid', '==', partnerUid).get()).size, 0);
});
