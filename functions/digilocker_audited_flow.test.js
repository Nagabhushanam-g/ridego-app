'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { newAuthorizationState } = require('./digilocker_state');
const { auditedPartnerDigiLockerSession, auditedDigiLockerCallback } = require('./digilocker_audited_flow');

test('unauthenticated session emits only allowlisted audit fields', async () => {
  const events = [];
  const result = await auditedPartnerDigiLockerSession({
    request: { data: { documentType: 'dl', code: 'SECRET' } },
    db: {}, now: 12345, audit: record => events.push(record),
  });
  assert.deepEqual(result, { ok: false, errorCode: 'unauthenticated' });
  assert.deepEqual(events, [{
    component: 'digilocker', event: 'session_rejected',
    timestampMs: 12345, reason: 'unauthenticated',
  }]);
});

test('invalid callback emits safe audit metadata without state or code', async () => {
  const events = [];
  const state = newAuthorizationState();
  const result = await auditedDigiLockerCallback({
    query: { state, code: 'SECRET-CODE' },
    db: { collection() { throw new Error('access_token=SECRET-TOKEN'); } },
    now: 12345, audit: record => events.push(record),
  });
  assert.deepEqual(result, { ok: false, errorCode: 'internal' });
  assert.deepEqual(events, [{
    component: 'digilocker', event: 'callback_rejected',
    timestampMs: 12345, reason: 'internal_error',
  }]);
  assert.equal(JSON.stringify(events).includes(state), false);
  assert.equal(JSON.stringify(events).includes('SECRET'), false);
});

test('audit sink failure does not change authorization failure response', async () => {
  const result = await auditedPartnerDigiLockerSession({
    request: {}, db: {}, now: 12345,
    audit: async () => { throw new Error('audit service unavailable'); },
  });
  assert.deepEqual(result, { ok: false, errorCode: 'unauthenticated' });
});
