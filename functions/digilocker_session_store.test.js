'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { persistAuthorizationSession } = require('./digilocker_session_store');
const { hashAuthorizationState, validateAuthorizationCallback } = require('./digilocker_state');

test('persists only a hashed authorization state and owner', async () => {
  let stored;
  const db = { collection(name) {
    assert.equal(name, 'digilockerAuthorizationSessions');
    return { doc(id) {
      assert.match(id, /^[A-Za-z0-9_-]{32}$/);
      return { async create(data) { stored = { id, ...data }; } };
    } };
  } };
  const result = await persistAuthorizationSession({
    db, uid: 'partner-1', documentType: 'rc', now: 1000,
  });
  assert.equal(stored.id, result.sessionId);
  assert.equal(stored.uid, 'partner-1');
  assert.equal(stored.documentType, 'rc');
  assert.equal(stored.stateHash, hashAuthorizationState(result.state));
  assert.equal(stored.state, undefined);
  assert.equal(result.expiresAtMs, stored.expiresAtMs);
  assert.equal(validateAuthorizationCallback({
    state: result.state, session: stored, uid: 'partner-1', now: 2000,
  }), true);
});

test('rejects missing database and unsupported document type', async () => {
  await assert.rejects(persistAuthorizationSession({
    db: null, uid: 'partner-1', documentType: 'rc',
  }));
  await assert.rejects(persistAuthorizationSession({
    db: { collection() { throw new Error('should not write'); } },
    uid: 'partner-1', documentType: 'passport',
  }));
});
