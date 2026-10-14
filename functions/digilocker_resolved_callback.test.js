'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { newAuthorizationState, hashAuthorizationState } = require('./digilocker_state');
const { processResolvedDigiLockerCallback } = require('./digilocker_resolved_callback');

function fakeDb(state, uid = 'partner-1') {
  const ref = {};
  const session = { uid, stateHash: hashAuthorizationState(state),
    createdAtMs: 1000, consumed: false };
  return { collection() {
    return { where(_field, _op, hash) {
      return { limit() {
        return { async get() {
          return hash === session.stateHash
            ? { size: 1, docs: [{ ref, get: field => session[field] }] }
            : { size: 0, docs: [] };
        } };
      } };
    } };
  }, async runTransaction(fn) {
    return fn({
      async get(givenRef) {
        assert.equal(givenRef, ref);
        return { exists: true, data: () => ({ ...session }) };
      },
      update(givenRef, patch) {
        assert.equal(givenRef, ref);
        Object.assign(session, patch);
      },
    });
  } };
}

test('valid callback uses server-owned uid and rejects replay', async () => {
  const state = newAuthorizationState();
  const db = fakeDb(state);
  const query = { state, code: 'authorization-code', uid: 'forged-uid' };
  assert.deepEqual(await processResolvedDigiLockerCallback({
    db, query, now: 2000,
  }), { ok: true, outcome: 'authorized', code: 'authorization-code' });
  assert.deepEqual(await processResolvedDigiLockerCallback({
    db, query, now: 2001,
  }), { ok: false, reason: 'invalid_or_expired_session' });
});

test('denied callback consumes state and does not return a code', async () => {
  const state = newAuthorizationState();
  const db = fakeDb(state);
  assert.deepEqual(await processResolvedDigiLockerCallback({
    db, query: { state, error: 'access_denied' }, now: 2000,
  }), { ok: true, outcome: 'denied' });
});


test('lookup failure returns a fixed error without leaking OAuth secrets', async () => {
  const state = newAuthorizationState();
  const secret = 'code=secret-code; access_token=secret-token';
  const db = { collection() { throw new Error(secret); } };
  const result = await processResolvedDigiLockerCallback({
    db, query: { state, code: 'secret-code' }, now: 2000,
  });
  assert.deepEqual(result, { ok: false, errorCode: 'internal' });
  assert.equal(JSON.stringify(result).includes('secret'), false);
});

test('transaction failure returns a fixed error without leaking stored data', async () => {
  const state = newAuthorizationState();
  const db = fakeDb(state);
  db.runTransaction = async () => { throw new Error('DL-SECRET access_token=secret'); };
  assert.deepEqual(await processResolvedDigiLockerCallback({
    db, query: { state, code: 'secret-code' }, now: 2000,
  }), { ok: false, errorCode: 'internal' });
});
