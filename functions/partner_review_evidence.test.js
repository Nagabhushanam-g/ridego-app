'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {validatePartnerEvidence} = require('./partner_review_evidence');
const now = Date.now();
const valid = {
  partnerUid: 'partner-1', verified: true, revoked: false,
  source: 'digilocker', documentType: 'registration_certificate',
  issuer: 'trusted-service', sourceReference: 'ref-123',
  verifiedAtMs: now - 1000, expiresAtMs: now + 86400000
};
const doc = fields => ({exists: true, get: key => fields[key]});
test('complete unexpired attestation passes structural validation', () => {
  assert.equal(validatePartnerEvidence(doc(valid), {partnerUid: 'partner-1', now}), true);
});
test('missing provenance, expiry and incorrect ownership fail closed', () => {
  for (const changes of [
    {source: 'manual_upload'}, {issuer: ''}, {sourceReference: ''},
    {documentType: 'unknown'}, {partnerUid: 'another-partner'},
    {verified: false}, {revoked: true}, {expiresAtMs: now},
    {verifiedAtMs: now + 1000}
  ]) {
    assert.equal(validatePartnerEvidence(doc({...valid, ...changes}), {partnerUid: 'partner-1', now}), false);
  }
  assert.equal(validatePartnerEvidence(doc({partnerUid: 'partner-1', verified: true}), {partnerUid: 'partner-1', now}), false);
});
