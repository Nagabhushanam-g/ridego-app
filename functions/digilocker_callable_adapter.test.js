'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { handlePartnerDigiLockerCallable } = require('./digilocker_callable_adapter');

function fakeDb(role) {
  let sessionCount = 0;
  let quota = null;
  const rateRef = {};
  return {
    get sessionCount() { return sessionCount; },
    collection(name) {
      if (name === 'profiles') return { doc(uid) { return { async get() {
        return { exists: role !== null, get: key => key === 'role' ? role : undefined };
      } }; } };
      if (name === 'digilockerPartnerRateLimits') return { doc() { return rateRef; } };
      if (name === 'digilockerAuthorizationSessions') return { doc() { return {}; } };
      throw new Error('Unexpected collection: ' + name);
    },
    async runTransaction(fn) {
      return fn({
        async get(ref) {
          assert.equal(ref, rateRef);
          return { exists: quota !== null, data: () => quota };
        },
        create() { sessionCount++; },
        set(ref, value) { assert.equal(ref, rateRef); quota = value; },
      });
    },
  };
}

test('rejects unsigned and non-Partner requests without session writes', async () => {
  const db = fakeDb('driver');
  assert.deepEqual(await handlePartnerDigiLockerCallable({
    db, request: { data: { documentType: 'dl' } },
  }), { ok: false, errorCode: 'unauthenticated' });
  assert.equal(db.sessionCount, 0);
  const riderDb = fakeDb('rider');
  assert.deepEqual(await handlePartnerDigiLockerCallable({
    db: riderDb, request: { auth: { uid: 'rider-1' }, data: { documentType: 'dl' } },
  }), { ok: false, errorCode: 'permission-denied' });
  assert.equal(riderDb.sessionCount, 0);
});

test('accepts only authenticated owner and maps duplicate attempt to resource-exhausted', async () => {
  const db = fakeDb('driver');
  const request = { auth: { uid: 'partner-1' },
    data: { documentType: 'rc', uid: 'forged', now: 0 } };
  const first = await handlePartnerDigiLockerCallable({ db, request, now: 1000000 });
  assert.equal(first.ok, true);
  assert.equal(typeof first.state, 'string');
  assert.equal(first.state.length, 43);
  assert.equal(first.stateHash, undefined);
  const second = await handlePartnerDigiLockerCallable({ db, request, now: 1000001 });
  assert.deepEqual(second, { ok: false, errorCode: 'resource-exhausted' });
  assert.equal(db.sessionCount, 1);
});

test('rejects invalid document type before writing', async () => {
  const db = fakeDb('driver');
  assert.deepEqual(await handlePartnerDigiLockerCallable({
    db, request: { auth: { uid: 'partner-1' }, data: { documentType: 'passport' } },
  }), { ok: false, errorCode: 'invalid-argument' });
  assert.equal(db.sessionCount, 0);
});
