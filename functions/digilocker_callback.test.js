'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { newAuthorizationState } = require('./digilocker_state');
const { parseDigiLockerCallback } = require('./digilocker_callback');

test('accepts exactly one of authorization code or denied consent', () => {
  const state = newAuthorizationState();
  assert.deepEqual(parseDigiLockerCallback({ state, code: 'example-code' }),
    { ok: true, outcome: 'authorized', state, code: 'example-code' });
  assert.deepEqual(parseDigiLockerCallback({ state, error: 'access_denied' }),
    { ok: true, outcome: 'denied', state, error: 'access_denied' });
  assert.equal(parseDigiLockerCallback({ state, code: 'a', error: 'access_denied' }).ok, false);
  assert.equal(parseDigiLockerCallback({ state }).ok, false);
});

test('rejects malformed callback parameters', () => {
  const state = newAuthorizationState();
  for (const query of [null, [], { state: 'bad', code: 'x' },
    { state, code: '' }, { state, code: 'x'.repeat(2049) },
    { state, code: 'a\nb' }, { state, code: ['a', 'b'] },
    { state, error: 'a b' }, { state, error: ['access_denied'] }]) {
    assert.equal(parseDigiLockerCallback(query).ok, false);
  }
});
