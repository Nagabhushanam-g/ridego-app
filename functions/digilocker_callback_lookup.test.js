'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { newAuthorizationState, hashAuthorizationState } = require('./digilocker_state');
const { resolveDigiLockerCallbackSession } = require('./digilocker_callback_lookup');

function fakeDb(rows) {
  return { collection(name) {
    assert.equal(name, 'digilockerAuthorizationSessions');
    return { where(field, operator, hash) {
      assert.equal(field, 'stateHash');
      assert.equal(operator, '==');
      return { limit(count) {
        assert.equal(count, 2);
        return { async get() {
          const docs = rows.filter(r => r.stateHash === hash).slice(0, count)
            .map(r => ({ ref: r.ref, get: key => r[key] }));
          return { size: docs.length, docs };
        } };
      } };
    } };
  } };
}

test('finds owner from hashed state without relying on callback uid', async () => {
  const state = newAuthorizationState();
  const ref = { id: 'session-1' };
  const result = await resolveDigiLockerCallbackSession({
    db: fakeDb([{ stateHash: hashAuthorizationState(state), uid: 'partner-1', ref }]),
    state,
  });
  assert.deepEqual(result, { ok: true, uid: 'partner-1', sessionRef: ref });
});

test('rejects missing, duplicate and invalid-owner matches', async () => {
  const state = newAuthorizationState();
  const hash = hashAuthorizationState(state);
  assert.equal((await resolveDigiLockerCallbackSession({ db: fakeDb([]), state })).ok, false);
  assert.deepEqual(await resolveDigiLockerCallbackSession({
    db: fakeDb([
      { stateHash: hash, uid: 'partner-1', ref: {} },
      { stateHash: hash, uid: 'partner-2', ref: {} },
    ]), state,
  }), { ok: false, reason: 'session_not_unique' });
  assert.deepEqual(await resolveDigiLockerCallbackSession({
    db: fakeDb([{ stateHash: hash, uid: '', ref: {} }]), state,
  }), { ok: false, reason: 'invalid_owner' });
});

test('rejects malformed state without querying database', async () => {
  assert.deepEqual(await resolveDigiLockerCallbackSession({
    db: { collection() { throw new Error('must not query'); } }, state: 'invalid',
  }), { ok: false, reason: 'invalid_state' });
});
