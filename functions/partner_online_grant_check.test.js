'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {checkPartnerOnlineGrant} = require('./partner_online_grant_check');
const now = 1700000000000;
const partnerUid = 'partner-1';
const ids = ['rc-1', 'dl-1'];
const base = {
  partnerUid, verified: true, revoked: false, source: 'digilocker',
  issuer: 'trusted-service', sourceReference: 'ref-123',
  verifiedAtMs: now - 1000, expiresAtMs: now + 10000
};
const fixtures = {
  partnerOnlineAuthorizations: {[partnerUid]: {
    authorized: true, reviewRevision: 3, evidenceIds: ids
  }},
  partnerVerifications: {[partnerUid]: {
    status: 'approved', reviewRevision: 3, evidenceIds: ids
  }},
  partnerReviewEvidence: {
    'rc-1': {...base, documentType: 'registration_certificate'},
    'dl-1': {...base, documentType: 'driving_licence'}
  }
};
function db(data, fails = false) {
  return {collection(name) {
    return {doc(id) {
      return {async get() {
        if (fails) throw Error('internal');
        const value = data[name]?.[id];
        return {id, exists: !!value, get: key => value?.[key]};
      }};
    }};
  }};
}

test('current authorization with both valid documents is accepted', async () => {
  assert.deepEqual(await checkPartnerOnlineGrant({db: db(fixtures), partnerUid, now}),
    {allowed: true, reason: 'verified_documents'});
});

test('expired or revoked DL invalidates previously approved grant immediately', async () => {
  for (const change of [{expiresAtMs: now}, {revoked: true}, {verified: false}]) {
    const data = structuredClone(fixtures);
    Object.assign(data.partnerReviewEvidence['dl-1'], change);
    assert.equal((await checkPartnerOnlineGrant({
      db: db(data), partnerUid, now
    })).allowed, false);
  }
});

test('changed review revision, evidence ids and missing grant fail closed', async () => {
  for (const modify of [
    d => {d.partnerVerifications[partnerUid].reviewRevision = 4;},
    d => {d.partnerOnlineAuthorizations[partnerUid].evidenceIds = ['dl-1', 'rc-1'];},
    d => {d.partnerOnlineAuthorizations[partnerUid].authorized = false;},
    d => {d.partnerVerifications[partnerUid].status = 'needs_review';},
    d => {delete d.partnerOnlineAuthorizations[partnerUid];}
  ]) {
    const data = structuredClone(fixtures);
    modify(data);
    assert.equal((await checkPartnerOnlineGrant({
      db: db(data), partnerUid, now
    })).allowed, false);
  }
});

test('database failures deny authorization', async () => {
  assert.deepEqual(await checkPartnerOnlineGrant({
    db: db(fixtures, true), partnerUid, now
  }), {allowed: false, reason: 'verification_unavailable'});
});
