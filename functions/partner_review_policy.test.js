'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {preparePartnerReviewDecision: decide} = require('./partner_review_policy');

const base = {
  reviewerUid: 'trusted-reviewer', reviewerAuthorized: true,
  partnerUid: 'partner-123', status: 'approved',
  reasonCode: 'verification_complete', now: 1700000000000
};

test('accepts a valid authorized review decision', () => {
  const result = decide(base);
  assert.equal(result.ok, true);
  assert.equal(result.partnerUid, base.partnerUid);
  assert.deepEqual(result.record, {
    status: 'approved', reasonCode: 'verification_complete',
    reviewedBy: 'trusted-reviewer', reviewedAtMs: base.now
  });
});

test('rejects untrusted reviewer and self review', () => {
  for (const change of [
    {reviewerAuthorized: false}, {reviewerAuthorized: 'true'},
    {reviewerUid: ''}, {reviewerUid: 'bad/uid'},
    {reviewerUid: base.partnerUid}
  ]) assert.equal(decide({...base, ...change}).ok, false);
});

test('rejects invalid status, reason, partner and clock', () => {
  for (const change of [
    {partnerUid: '../other'}, {partnerUid: ''},
    {status: 'verified'}, {status: 'approved', reasonCode: 'manual_review'},
    {status: 'rejected', reasonCode: 'verification_complete'},
    {reasonCode: 'custom_user_supplied'}, {now: NaN}, {now: -1}
  ]) assert.equal(decide({...base, ...change}).ok, false);
});

test('accepts pending manual review without granting approval', () => {
  const result = decide({...base, status: 'needs_review', reasonCode: 'manual_review'});
  assert.equal(result.ok, true);
  assert.equal(result.record.status, 'needs_review');
});
