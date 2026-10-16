'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {validateAccountDeletionRequest: validate} = require('./account_deletion_request_validation');

test('owner may submit a non-destructive request when no ride is active', () => {
  assert.deepEqual(validate({
    authUid: 'rider-123', targetUid: 'rider-123',
    reason: 'privacy', activeRide: false
  }), {ok: true, reason: 'request_eligible'});
});

test('missing identity and cross-account requests are rejected', () => {
  assert.equal(validate({
    authUid: '', targetUid: 'rider-123', reason: 'privacy'
  }).reason, 'unauthenticated');
  assert.equal(validate({
    authUid: 'rider-123', targetUid: 'partner-456', reason: 'privacy'
  }).reason, 'permission_denied');
});

test('active ride and unknown ride state are not eligible', () => {
  assert.equal(validate({
    authUid: 'partner-123', targetUid: 'partner-123',
    reason: 'other', activeRide: true
  }).reason, 'active_ride');
  assert.equal(validate({
    authUid: 'partner-123', targetUid: 'partner-123',
    reason: 'other', activeRide: undefined
  }).reason, 'invalid_active_ride_state');
});

test('unsupported reasons are rejected', () => {
  assert.equal(validate({
    authUid: 'rider-123', targetUid: 'rider-123',
    reason: 'delete_everyone', activeRide: false
  }).reason, 'invalid_reason');
});
