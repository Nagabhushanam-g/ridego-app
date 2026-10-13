'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { STATE_TTL_MS, newAuthorizationState, hashAuthorizationState, validateAuthorizationCallback } = require('./digilocker_state');

test('valid state is random and can be validated for its owner', () => {
  const state = newAuthorizationState();
  assert.notEqual(state, newAuthorizationState());
  assert.equal(state.length, 43);
  const session = { uid: 'partner-1', stateHash: hashAuthorizationState(state), createdAtMs: 1000, consumed: false };
  assert.equal(validateAuthorizationCallback({ state, session, uid: 'partner-1', now: 2000 }), true);
  assert.equal(validateAuthorizationCallback({ state, session, uid: 'partner-2', now: 2000 }), false);
  assert.equal(validateAuthorizationCallback({ state: newAuthorizationState(), session, uid: 'partner-1', now: 2000 }), false);
});

test('rejects consumed, expired, future and malformed callback states', () => {
  const state = newAuthorizationState();
  const session = { uid: 'partner-1', stateHash: hashAuthorizationState(state), createdAtMs: 1000, consumed: false };
  const valid = { state, session, uid: 'partner-1' };
  assert.equal(validateAuthorizationCallback({ ...valid, now: 1000 + STATE_TTL_MS - 1 }), true);
  assert.equal(validateAuthorizationCallback({ ...valid, now: 1000 + STATE_TTL_MS }), false);
  assert.equal(validateAuthorizationCallback({ ...valid, now: 999 }), false);
  assert.equal(validateAuthorizationCallback({ ...valid, session: { ...session, consumed: true }, now: 2000 }), false);
  assert.equal(validateAuthorizationCallback({ ...valid, state: 'bad', now: 2000 }), false);
  assert.equal(validateAuthorizationCallback({ ...valid, session: { ...session, stateHash: 'bad' }, now: 2000 }), false);
});
