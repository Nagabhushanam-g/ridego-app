'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {handleAccountDeletionCallable} = require('./account_deletion_callable_adapter');

function fakeDb({active = false, existing = false, fail = false} = {}) {
  let writes = 0;
  const requestRef = {kind: 'request'};
  return {
    get writes() { return writes; },
    collection(name) {
      if (name === 'accountDeletionRequests') return {doc: () => requestRef};
      if (name === 'rideRequests') return {
        where() {return {where() {return {limit() {return {kind: 'query'};}};}};}
      };
      throw Error('unexpected collection');
    },
    async runTransaction(fn) {
      if (fail) throw Error('database access_token=secret');
      return fn({
        async get(ref) {
          if (ref === requestRef) return {exists: existing};
          return {empty: !active};
        },
        create() {writes++;}
      });
    }
  };
}

test('anonymous, forged and malformed requests never write', async () => {
  const db = fakeDb();
  for (const request of [
    {data: {reason: 'privacy'}},
    {auth: {uid: 'partner-1'}, data: {reason: 'privacy', targetUid: 'other'}},
    {auth: {uid: 'partner-1'}, data: {reason: 'privacy', uid: 'other'}},
    {auth: {uid: 'partner-1'}, data: {reason: 'unknown'}}
  ]) {
    assert.equal((await handleAccountDeletionCallable({request, db})).ok, false);
  }
  assert.equal(db.writes, 0);
});

test('authenticated request queues once and returns only safe status', async () => {
  const db = fakeDb();
  assert.deepEqual(await handleAccountDeletionCallable({
    request: {auth: {uid: 'partner-1'}, data: {reason: 'privacy'}}, db
  }), {ok: true, status: 'pending_review'});
  assert.equal(db.writes, 1);
  const repeat = fakeDb({existing: true});
  assert.deepEqual(await handleAccountDeletionCallable({
    request: {auth: {uid: 'partner-1'}, data: {reason: 'privacy'}}, db: repeat
  }), {ok: true, status: 'already_requested'});
  assert.equal(repeat.writes, 0);
});

test('active trips block requests and internal failures leak no secrets', async () => {
  const request = {auth: {uid: 'partner-1'}, data: {reason: 'privacy'}};
  const active = fakeDb({active: true});
  assert.deepEqual(await handleAccountDeletionCallable({request, db: active}),
    {ok: false, errorCode: 'failed-precondition'});
  assert.equal(active.writes, 0);
  const error = await handleAccountDeletionCallable({request, db: fakeDb({fail: true})});
  assert.deepEqual(error, {ok: false, errorCode: 'unavailable'});
  assert.equal(JSON.stringify(error).includes('secret'), false);
});
