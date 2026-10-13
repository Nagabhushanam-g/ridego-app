'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { deleteExpiredAuthorizationSessions } = require('./digilocker_cleanup');

function fakeDb(docs) {
  const removed = [];
  let cutoff;
  let max;
  const db = {
    collection(name) {
      assert.equal(name, 'digilockerAuthorizationSessions');
      return { where(field, operator, value) {
        assert.equal(field, 'createdAtMs');
        assert.equal(operator, '<=');
        cutoff = value;
        return { orderBy(field) {
          assert.equal(field, 'createdAtMs');
          return { limit(n) {
            max = n;
            return { async get() {
              const eligible = docs.filter(d => d.createdAtMs <= cutoff).slice(0, max);
              return { empty: eligible.length === 0, size: eligible.length,
                docs: eligible.map(d => ({ ref: d })) };
            } };
          } };
        } };
      } };
    },
    batch() { return {
      delete(ref) { removed.push(ref); },
      async commit() {},
    }; },
  };
  return { db, removed };
}

test('deletes only expired sessions in a bounded batch', async () => {
  const store = fakeDb([
    { createdAtMs: 1 }, { createdAtMs: 2 }, { createdAtMs: 900000 },
  ]);
  assert.equal(await deleteExpiredAuthorizationSessions({
    db: store.db, now: 600002, limit: 1,
  }), 1);
  assert.equal(store.removed.length, 1);
  assert.equal(store.removed[0].createdAtMs, 1);
});

test('returns zero when nothing has expired', async () => {
  const store = fakeDb([{ createdAtMs: 10000 }]);
  assert.equal(await deleteExpiredAuthorizationSessions({
    db: store.db, now: 11000,
  }), 0);
  assert.equal(store.removed.length, 0);
});

test('rejects invalid cleanup limits', async () => {
  await assert.rejects(deleteExpiredAuthorizationSessions({
    db: fakeDb([]).db, now: 1000, limit: 501,
  }));
});
