'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {assessPartnerOnlineEligibility} = require('./partner_online_assessment');

const now = 1700000000000;
const partnerUid = 'partner-1';
const docs = {
  profiles: {[partnerUid]: {role: 'driver'}},
  partnerVerifications: {[partnerUid]: {
    status: 'approved', evidenceIds: ['rc-1', 'dl-1']
  }},
  partnerReviewEvidence: {
    'rc-1': {partnerUid, verified: true, revoked: false, source: 'digilocker',
      documentType: 'registration_certificate', issuer: 'trusted-service',
      sourceReference: 'ref-123', verifiedAtMs: now - 1000, expiresAtMs: now + 10000},
    'dl-1': {partnerUid, verified: true, revoked: false, source: 'digilocker',
      documentType: 'driving_licence', issuer: 'trusted-service',
      sourceReference: 'ref-456', verifiedAtMs: now - 1000, expiresAtMs: now + 10000}
  }
};
function fakeDb(data = docs, fail = false) {
  return {collection(name) {
    return {doc(id) {
      return {async get() {
        if (fail) throw new Error('private failure');
        const value = data[name]?.[id];
        return {id, exists: !!value, get: key => value?.[key]};
      }};
    }};
  }};
}

test('legacy compatibility does not require document evidence', async () => {
  const data = structuredClone(docs);
  delete data.partnerVerifications[partnerUid];
  assert.deepEqual(await assessPartnerOnlineEligibility({
    db: fakeDb(data), partnerUid, now
  }), {allowed: true, reason: 'legacy_rollout'});
});

test('enforced assessment requires both valid RC and DL', async () => {
  assert.deepEqual(await assessPartnerOnlineEligibility({
    db: fakeDb(), partnerUid, now, enforcementEnabled: true
  }), {allowed: true, reason: 'verified_documents'});
  for (const override of [
    {revoked: true}, {verified: false}, {expiresAtMs: now},
    {partnerUid: 'other-partner'}, {documentType: 'registration_certificate'}
  ]) {
    const data = structuredClone(docs);
    Object.assign(data.partnerReviewEvidence['dl-1'], override);
    const result = await assessPartnerOnlineEligibility({
      db: fakeDb(data), partnerUid, now, enforcementEnabled: true
    });
    assert.equal(result.allowed, false);
  }
});

test('database failure denies eligibility even in legacy mode', async () => {
  assert.deepEqual(await assessPartnerOnlineEligibility({
    db: fakeDb(docs, true), partnerUid, now
  }), {allowed: false, reason: 'verification_unavailable'});
});

test('missing approval and missing evidence deny enforced eligibility', async () => {
  const data = structuredClone(docs);
  data.partnerVerifications[partnerUid].status = 'needs_review';
  assert.equal((await assessPartnerOnlineEligibility({
    db: fakeDb(data), partnerUid, now, enforcementEnabled: true
  })).allowed, false);
  data.partnerVerifications[partnerUid].status = 'approved';
  delete data.partnerReviewEvidence['dl-1'];
  assert.equal((await assessPartnerOnlineEligibility({
    db: fakeDb(data), partnerUid, now, enforcementEnabled: true
  })).allowed, false);
});
