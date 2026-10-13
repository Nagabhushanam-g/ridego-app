'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { newAuthorizationState, hashAuthorizationState } = require('./digilocker_state');
const { processDigiLockerCallback } = require('./digilocker_callback_flow');

function store(state) {
  const data = { uid: 'partner-1', stateHash: hashAuthorizationState(state), createdAtMs: 1000, consumed: false };
  const sessionRef = {};
  const db = { runTransaction: async (fn) => fn({
    get: async () => ({ exists: true, data: () => ({ ...data }) }),
    update: (_ref, patch) => Object.assign(data, patch),
  }) };
  return { db, sessionRef, data };
}

test('accepts once and rejects a replay', async () => {
  const state = newAuthorizationState();
  const s = store(state);
  const args = { ...s, uid: 'partner-1', now: 2000, query: { state, code: 'test-code' } };
  assert.deepEqual(await processDigiLockerCallback(args),
    { ok: true, outcome: 'authorized', code: 'test-code' });
  assert.deepEqual(await processDigiLockerCallback(args),
    { ok: false, reason: 'invalid_or_expired_session' });
});

test('consent denial consumes session without returning an authorization code', async () => {
  const state = newAuthorizationState();
  const s = store(state);
  const result = await processDigiLockerCallback({
    ...s, uid: 'partner-1', now: 2000,
    query: { state, error: 'access_denied' },
  });
  assert.deepEqual(result, { ok: true, outcome: 'denied' });
  assert.equal(s.data.consumed, true);
});

test('wrong owner and malformed callback do not consume session', async () => {
  const state = newAuthorizationState();
  const s = store(state);
  const args = { ...s, uid: 'partner-2', now: 2000, query: { state, code: 'test-code' } };
  assert.equal((await processDigiLockerCallback(args)).ok, false);
  assert.equal(s.data.consumed, false);
  assert.deepEqual(await processDigiLockerCallback({ ...args, uid: 'partner-1', query: { state: 'bad', code: 'x' } }),
    { ok: false, reason: 'invalid_state' });
  assert.equal(s.data.consumed, false);
});
