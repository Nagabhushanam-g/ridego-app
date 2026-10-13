'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { reserveDigiLockerAttempt, MIN_INTERVAL_MS, WINDOW_MS } = require('./digilocker_rate_limit');

function fakeDb() {
  let data = null;
  const ref = {};
  return {
    collection(name) {
      assert.equal(name, 'digilockerPartnerRateLimits');
      return { doc(uid) { assert.equal(uid, 'partner-1'); return ref; } };
    },
    async runTransaction(fn) {
      return fn({
        async get(givenRef) {
          assert.equal(givenRef, ref);
          return { exists: data !== null, data: () => ({ ...data }) };
        },
        set(givenRef, patch) { assert.equal(givenRef, ref); data = { ...patch }; },
      });
    },
  };
}

test('enforces cooldown and five requests per hour', async () => {
  const db = fakeDb();
  const first = 1000000;
  const attempt = (now) => reserveDigiLockerAttempt({ db, uid: 'partner-1', now });
  assert.deepEqual(await attempt(first), { allowed: true });
  assert.deepEqual(await attempt(first + 1), { allowed: false, reason: 'cooldown' });
  for (let i = 1; i < 5; i++) {
    assert.deepEqual(await attempt(first + i * MIN_INTERVAL_MS), { allowed: true });
  }
  assert.deepEqual(await attempt(first + 5 * MIN_INTERVAL_MS),
    { allowed: false, reason: 'hourly_limit' });
  assert.deepEqual(await attempt(first + WINDOW_MS), { allowed: true });
});

test('rejects malformed Partner identity and timestamps', async () => {
  const db = fakeDb();
  await assert.rejects(reserveDigiLockerAttempt({ db, uid: '', now: 1000 }));
  await assert.rejects(reserveDigiLockerAttempt({ db, uid: 'partner-1', now: NaN }));
});
