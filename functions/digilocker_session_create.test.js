'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { createAuthorizationSession } = require('./digilocker_session_create');
const { STATE_TTL_MS, hashAuthorizationState, validateAuthorizationCallback } = require('./digilocker_state');

test('creates independent opaque sessions with hashed states', () => {
  const a = createAuthorizationSession({ uid: 'partner-1', documentType: 'dl', now: 1000 });
  const b = createAuthorizationSession({ uid: 'partner-1', documentType: 'dl', now: 1000 });
  assert.notEqual(a.state, b.state);
  assert.notEqual(a.sessionId, b.sessionId);
  assert.equal(a.record.stateHash, hashAuthorizationState(a.state));
  assert.equal(a.record.expiresAtMs, 1000 + STATE_TTL_MS);
  assert.equal(a.record.documentType, 'dl');
  assert.equal(validateAuthorizationCallback({
    state: a.state, session: a.record, uid: 'partner-1', now: 2000,
  }), true);
  assert.equal(JSON.stringify(a.record).includes(a.state), false);
});

test('accepts RC and rejects unsupported types and invalid owners', () => {
  assert.equal(createAuthorizationSession({ uid: 'partner-1', documentType: 'rc' }).record.documentType, 'rc');
  for (const args of [
    { uid: '', documentType: 'dl' },
    { uid: 'partner-1', documentType: 'aadhaar' },
    { uid: 'partner-1', documentType: 'dl', now: -1 },
    { uid: 'partner-1', documentType: 'dl', now: NaN },
  ]) {
    assert.throws(() => createAuthorizationSession(args));
  }
});
