'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { newAuthorizationState, hashAuthorizationState } = require('./digilocker_state');
const { consumeAuthorizationSession } = require('./digilocker_session');

function fakeStore(data) {
  const ref = { id: 'session-1' };
  const db = {
    async runTransaction(fn) {
      const tx = {
        async get(givenRef) {
          assert.equal(givenRef, ref);
          return { exists: data !== null, data: () => ({ ...data }) };
        },
        update(givenRef, patch) {
          assert.equal(givenRef, ref);
          Object.assign(data, patch);
        },
      };
      return fn(tx);
    },
  };
  return { db, ref, data };
}

test('consumes a valid session once, rejects a replay', async () => {
  const state = newAuthorizationState();
  const store = fakeStore({
    uid: 'partner-1', stateHash: hashAuthorizationState(state),
    createdAtMs: 1000, consumed: false,
  });
  const args = { db: store.db, sessionRef: store.ref, state, uid: 'partner-1', now: 2000 };
  assert.equal(await consumeAuthorizationSession(args), true);
  assert.equal(store.data.consumed, true);
  assert.equal(store.data.consumedAtMs, 2000);
  assert.equal(await consumeAuthorizationSession(args), false);
});

test('rejects a wrong partner and expired session without consuming', async () => {
  const state = newAuthorizationState();
  const store = fakeStore({
    uid: 'partner-1', stateHash: hashAuthorizationState(state),
    createdAtMs: 1000, consumed: false,
  });
  const args = { db: store.db, sessionRef: store.ref, state, uid: 'partner-2', now: 2000 };
  assert.equal(await consumeAuthorizationSession(args), false);
  assert.equal(await consumeAuthorizationSession({ ...args, uid: 'partner-1', now: 1000 + 600000 }), false);
  assert.equal(store.data.consumed, false);
});

test('rejects missing sessions', async () => {
  const store = fakeStore(null);
  assert.equal(await consumeAuthorizationSession({
    db: store.db, sessionRef: store.ref,
    state: newAuthorizationState(), uid: 'partner-1', now: 2000,
  }), false);
});
