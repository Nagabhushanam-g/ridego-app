'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {recordPartnerReview} = require('./partner_review_transaction');
const {preparePartnerReviewDecision} = require('./partner_review_policy');
const now = 1700000000000;
const decision = preparePartnerReviewDecision({
  reviewerUid: 'reviewer-1', reviewerAuthorized: true,
  partnerUid: 'partner-1', status: 'approved',
  reasonCode: 'verification_complete', now
});

function fakeDb({authorized = true, isPartner = true, fail = false, existingReview = false, evidenceVerified = true, evidencePartnerUid = 'partner-1'} = {}) {
  const writes = [];
  const db = {
    writes,
    collection(name) {
      return {doc(id) {return {name, id: id || 'audit-1'};}};
    },
    async runTransaction(fn) {
      const staged = [];
      const tx = {
        async get(ref) {
          if (fail) throw new Error('private database details');
          if (ref.name === 'partnerReviewEvidence') return {
            exists: true,
            get: key => ({partnerUid: evidencePartnerUid, verified: evidenceVerified, revoked: false, source: 'digilocker', documentType: ref.id.startsWith('dl-') ? 'driving_licence' : 'registration_certificate', issuer: 'trusted-service', sourceReference: 'ref-123', verifiedAtMs: now - 1000, expiresAtMs: now + 86400000})[key]
          };
          if (ref.name === 'partnerVerifications') return {exists: existingReview};
          if (ref.name === 'partnerReviewers') {
            return {exists: true, get: key => ({active: authorized, role: 'partner_reviewer'})[key]};
          }
          return {exists: true, get: key => ({role: isPartner ? 'driver' : 'rider'})[key]};
        },
        set(ref, value) {staged.push({type: 'set', ref, value});},
        create(ref, value) {staged.push({type: 'create', ref, value});}
      };
      await fn(tx);
      writes.push(...staged);
    }
  };
  return db;
}

test('writes verification and audit in the same transaction', async () => {
  const db = fakeDb();
  assert.deepEqual(await recordPartnerReview({db, decision, evidenceIds: ['rc-1', 'dl-1'], now}), {ok: true});
  assert.equal(db.writes.length, 2);
  assert.equal(db.writes[0].ref.name, 'partnerVerifications');
  assert.equal(db.writes[0].type, 'create');
  assert.equal(db.writes[1].ref.name, 'partnerReviewAudit');
  assert.equal(db.writes[0].value.status, 'approved');
  assert.deepEqual(db.writes[0].value.evidenceIds, ['rc-1', 'dl-1']);
});

test('unauthorized reviewer cannot write anything', async () => {
  const db = fakeDb({authorized: false});
  assert.equal((await recordPartnerReview({db, decision, evidenceIds: ['rc-evidence', 'dl-evidence'], now})).ok, false);
  assert.equal(db.writes.length, 0);
});

test('non-partner and database errors fail closed', async () => {
  for (const options of [{isPartner: false}, {fail: true}]) {
    const db = fakeDb(options);
    assert.equal((await recordPartnerReview({db, decision, evidenceIds: ['rc-evidence'], now})).ok, false);
    assert.equal(db.writes.length, 0);
  }
});

test('rejects invalid evidence and malformed decision', async () => {
  for (const change of [
    {evidenceIds: ['bad/path']},
    {evidenceIds: ['same', 'same']},
    {decision: {...decision, partnerUid: 'bad/path'}},
    {now: -1}
  ]) {
    const db = fakeDb();
    assert.equal((await recordPartnerReview({db, decision, evidenceIds: [], now, ...change})).ok, false);
    assert.equal(db.writes.length, 0);
  }
});

test('existing verification cannot be silently overwritten', async () => {
  const db = fakeDb({existingReview: true});
  const result = await recordPartnerReview({db, decision, evidenceIds: ['rc-evidence'], now});
  assert.equal(result.ok, false);
  assert.equal(db.writes.length, 0);
});

test('approval requires evidence reference and rejects forged reason', async () => {
  for (const change of [
    {evidenceIds: []},
    {decision: {...decision, record: {...decision.record, reasonCode: 'manual_review'}}}
  ]) {
    const db = fakeDb();
    const result = await recordPartnerReview({
      db, decision, evidenceIds: ['rc-evidence'], now, ...change
    });
    assert.equal(result.ok, false);
    assert.equal(db.writes.length, 0);
  }
});

test('rejects unverified and cross-partner evidence', async () => {
  for (const options of [
    {evidenceVerified: false},
    {evidencePartnerUid: 'another-partner'}
  ]) {
    const db = fakeDb(options);
    const result = await recordPartnerReview({db, decision, evidenceIds: ['rc-evidence'], now});
    assert.equal(result.ok, false);
    assert.equal(db.writes.length, 0);
  }
});


test('approval requires both verified RC and DL evidence types', async () => {
  for (const ids of [['rc-1'], ['dl-1'], ['rc-1', 'rc-2'], ['dl-1', 'dl-2']]) {
    const db = fakeDb();
    const result = await recordPartnerReview({db, decision, evidenceIds: ids, now});
    assert.equal(result.ok, false, ids.join(','));
    assert.equal(db.writes.length, 0);
  }
  const db = fakeDb();
  assert.deepEqual(await recordPartnerReview({db, decision, evidenceIds: ['rc-1', 'dl-1'], now}), {ok: true});
});
