'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {evaluatePartnerOnlineEligibility} = require('./partner_online_eligibility');

const snapshot = (id, data) => ({
  id, exists: data !== null, get: key => data?.[key]
});
const partnerUid = 'partner-1';
const profile = snapshot(partnerUid, {role: 'driver'});
const verification = snapshot(partnerUid, {
  status: 'approved', evidenceIds: ['rc-1', 'dl-1']
});

test('legacy rollout preserves valid driver online access by default', () => {
  assert.deepEqual(evaluatePartnerOnlineEligibility({partnerUid, profile, verification}),
    {allowed: true, reason: 'legacy_rollout'});
  assert.equal(evaluatePartnerOnlineEligibility({
    partnerUid, profile, verification: null, enforcementEnabled: false
  }).allowed, true);
});

test('invalid profiles and rider accounts are never eligible', () => {
  for (const invalid of [
    snapshot('other-partner', {role: 'driver'}),
    snapshot(partnerUid, {role: 'rider'}),
    snapshot(partnerUid, null)
  ]) {
    assert.equal(evaluatePartnerOnlineEligibility({
      partnerUid, profile: invalid, verification
    }).allowed, false);
  }
});

test('enforcement cannot trust approval status without current evidence recheck', () => {
  for (const doc of [
    verification,
    snapshot(partnerUid, {status: 'needs_review', evidenceIds: ['rc-1', 'dl-1']}),
    snapshot(partnerUid, {status: 'approved', evidenceIds: ['rc-1']}),
    snapshot(partnerUid, null),
    snapshot('other-partner', {status: 'approved', evidenceIds: ['rc-1', 'dl-1']})
  ]) {
    assert.equal(evaluatePartnerOnlineEligibility({
      partnerUid, profile, verification: doc, enforcementEnabled: true
    }).allowed, false);
  }
});
