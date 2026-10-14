'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {initializeApp, getApps} = require('firebase-admin/app');
const {getFirestore} = require('firebase-admin/firestore');
const {transitionPendingPartnerReview} = require('./partner_review_transition');
const {preparePartnerReviewDecision} = require('./partner_review_policy');

if (!process.env.FIRESTORE_EMULATOR_HOST) throw new Error('Firestore Emulator required');
if (!getApps().length) initializeApp({projectId: 'ridego-partner-review-test'});
const db = getFirestore('firestore-db-2');

test('simultaneous pending review transitions commit only one decision and audit', async () => {
  const suffix = Date.now().toString(36) + '-' + Math.random().toString(36).slice(2, 8);
  const partnerUid = 'pending-partner-' + suffix;
  const reviewerUids = ['reviewer-one-' + suffix, 'reviewer-two-' + suffix];
  const evidenceId = 'verified-rc-' + suffix;
  await db.collection('profiles').doc(partnerUid).set({uid: partnerUid, role: 'driver'});
  await db.collection('partnerVerifications').doc(partnerUid).set({
    status: 'pending', reviewRevision: 0, existingField: 'preserved'
  });
  await db.collection('partnerReviewEvidence').doc(evidenceId).set({
    partnerUid, verified: true, revoked: false, source: 'digilocker', documentType: 'registration_certificate', issuer: 'trusted-service', sourceReference: 'ref-123', verifiedAtMs: Date.now() - 1000, expiresAtMs: Date.now() + 86400000
  });
  await Promise.all(reviewerUids.map(uid =>
    db.collection('partnerReviewers').doc(uid).set({active: true, role: 'partner_reviewer'})
  ));
  const now = Date.now();
  const decisions = reviewerUids.map((reviewerUid, i) =>
    preparePartnerReviewDecision({
      reviewerUid, reviewerAuthorized: true, partnerUid,
      status: i === 0 ? 'approved' : 'rejected',
      reasonCode: i === 0 ? 'verification_complete' : 'document_mismatch', now
    })
  );
  const results = await Promise.all(decisions.map(decision =>
    transitionPendingPartnerReview({db, decision, evidenceIds: [evidenceId], now, expectedRevision: 0})
  ));
  assert.equal(results.filter(result => result.ok).length, 1);
  const updated = await db.collection('partnerVerifications').doc(partnerUid).get();
  assert.equal(updated.get('reviewRevision'), 1);
  assert.equal(updated.get('existingField'), 'preserved');
  assert.ok(['approved', 'rejected'].includes(updated.get('status')));
  const audits = await db.collection('partnerReviewAudit').where('partnerUid', '==', partnerUid).get();
  assert.equal(audits.size, 1);
  assert.equal(audits.docs[0].get('status'), updated.get('status'));
  const retry = await transitionPendingPartnerReview({
    db, decision: decisions[0], evidenceIds: [evidenceId], now, expectedRevision: 0
  });
  assert.equal(retry.ok, false);
  assert.equal((await db.collection('partnerReviewAudit').where('partnerUid', '==', partnerUid).get()).size, 1);
});

test('unverified evidence cannot approve a pending Partner', async () => {
  const suffix = Date.now().toString(36) + '-unverified';
  const partnerUid = 'pending-partner-' + suffix;
  const reviewerUid = 'reviewer-' + suffix;
  const evidenceId = 'unverified-' + suffix;
  await db.collection('profiles').doc(partnerUid).set({uid: partnerUid, role: 'driver'});
  await db.collection('partnerVerifications').doc(partnerUid).set({status: 'pending'});
  await db.collection('partnerReviewers').doc(reviewerUid).set({active: true, role: 'partner_reviewer'});
  await db.collection('partnerReviewEvidence').doc(evidenceId).set({partnerUid, verified: false});
  const now = Date.now();
  const decision = preparePartnerReviewDecision({
    reviewerUid, reviewerAuthorized: true, partnerUid,
    status: 'approved', reasonCode: 'verification_complete', now
  });
  assert.equal((await transitionPendingPartnerReview({
    db, decision, evidenceIds: [evidenceId], now, expectedRevision: 0
  })).ok, false);
  assert.equal((await db.collection('partnerVerifications').doc(partnerUid).get()).get('status'), 'pending');
  assert.equal((await db.collection('partnerReviewAudit').where('partnerUid', '==', partnerUid).get()).size, 0);
});

test('rejection may omit evidence, but approval may not', async () => {
  const suffix = Date.now().toString(36) + '-no-evidence';
  const partnerUid = 'pending-partner-' + suffix;
  const reviewerUid = 'reviewer-' + suffix;
  await db.collection('profiles').doc(partnerUid).set({uid: partnerUid, role: 'driver'});
  await db.collection('partnerVerifications').doc(partnerUid).set({status: 'pending'});
  await db.collection('partnerReviewers').doc(reviewerUid).set({active: true, role: 'partner_reviewer'});
  const now = Date.now();
  const approved = preparePartnerReviewDecision({
    reviewerUid, reviewerAuthorized: true, partnerUid,
    status: 'approved', reasonCode: 'verification_complete', now
  });
  const rejected = preparePartnerReviewDecision({
    reviewerUid, reviewerAuthorized: true, partnerUid,
    status: 'rejected', reasonCode: 'documents_incomplete', now
  });
  assert.equal((await transitionPendingPartnerReview({
    db, decision: approved, evidenceIds: [], now, expectedRevision: 0
  })).ok, false);
  assert.equal((await transitionPendingPartnerReview({
    db, decision: rejected, evidenceIds: [], now, expectedRevision: 0
  })).ok, true);
  const result = await db.collection('partnerVerifications').doc(partnerUid).get();
  assert.equal(result.get('status'), 'rejected');
  assert.equal(result.get('reviewRevision'), 1);
  assert.equal((await db.collection('partnerReviewAudit').where('partnerUid', '==', partnerUid).get()).size, 1);
});

test('inactive reviewer cannot transition a pending Partner or write audit', async () => {
  const suffix = Date.now().toString(36) + '-inactive-reviewer';
  const partnerUid = 'pending-partner-' + suffix;
  const reviewerUid = 'reviewer-' + suffix;
  await db.collection('profiles').doc(partnerUid).set({uid: partnerUid, role: 'driver'});
  await db.collection('partnerVerifications').doc(partnerUid).set({status: 'pending', reviewRevision: 0});
  await db.collection('partnerReviewers').doc(reviewerUid).set({active: false, role: 'partner_reviewer'});
  const now = Date.now();
  const decision = preparePartnerReviewDecision({
    reviewerUid, reviewerAuthorized: true, partnerUid,
    status: 'rejected', reasonCode: 'documents_incomplete', now
  });
  const result = await transitionPendingPartnerReview({
    db, decision, evidenceIds: [], now, expectedRevision: 0
  });
  assert.equal(result.ok, false);
  assert.equal((await db.collection('partnerVerifications').doc(partnerUid).get()).get('status'), 'pending');
  assert.equal((await db.collection('partnerReviewAudit').where('partnerUid', '==', partnerUid).get()).size, 0);
});

test('wrong expected revision cannot transition pending verification', async () => {
  const suffix = Date.now().toString(36) + '-stale-revision';
  const partnerUid = 'pending-partner-' + suffix;
  const reviewerUid = 'reviewer-' + suffix;
  await db.collection('profiles').doc(partnerUid).set({uid: partnerUid, role: 'driver'});
  await db.collection('partnerVerifications').doc(partnerUid).set({status: 'pending', reviewRevision: 2});
  await db.collection('partnerReviewers').doc(reviewerUid).set({active: true, role: 'partner_reviewer'});
  const now = Date.now();
  const decision = preparePartnerReviewDecision({
    reviewerUid, reviewerAuthorized: true, partnerUid,
    status: 'rejected', reasonCode: 'documents_incomplete', now
  });
  const result = await transitionPendingPartnerReview({
    db, decision, evidenceIds: [], now, expectedRevision: 1
  });
  assert.equal(result.ok, false);
  const verification = await db.collection('partnerVerifications').doc(partnerUid).get();
  assert.equal(verification.get('status'), 'pending');
  assert.equal(verification.get('reviewRevision'), 2);
  assert.equal((await db.collection('partnerReviewAudit').where('partnerUid', '==', partnerUid).get()).size, 0);
});
