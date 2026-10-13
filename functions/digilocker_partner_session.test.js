'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { preparePartnerDigiLockerSession } = require('./digilocker_partner_session');

function fakeDb(role) {
  let writes = 0;
  let saved;
  const db = { collection(name) {
    if (name === 'profiles') return { doc() { return { async get() {
      return { exists: role !== null, get: (field) => field === 'role' ? role : undefined };
    } }; } };
    if (name === 'digilockerAuthorizationSessions') return { doc() { return {
      async create(record) { writes++; saved = record; },
    }; } };
    throw new Error('Unexpected collection');
  } };
  return { db, get writes() { return writes; }, get saved() { return saved; } };
}

test('allows signed-in driver to prepare DL session', async () => {
  const s = fakeDb('driver');
  const result = await preparePartnerDigiLockerSession({
    db: s.db, request: { auth: { uid: 'partner-1' }, data: { documentType: 'dl', uid: 'forged' } }, now: 1000,
  });
  assert.equal(result.ok, true);
  assert.equal(s.writes, 1);
  assert.equal(s.saved.uid, 'partner-1');
  assert.equal(s.saved.documentType, 'dl');
  assert.equal(s.saved.state, undefined);
});

test('rejects unauthenticated, rider, missing profile and unsupported types', async () => {
  for (const [role, request, reason] of [
    ['driver', { data: { documentType: 'dl' } }, 'unauthenticated'],
    ['rider', { auth: { uid: 'rider-1' }, data: { documentType: 'dl' } }, 'not_partner'],
    [null, { auth: { uid: 'unknown' }, data: { documentType: 'rc' } }, 'not_partner'],
    ['driver', { auth: { uid: 'partner-1' }, data: { documentType: 'passport' } }, 'invalid_document_type'],
  ]) {
    const s = fakeDb(role);
    assert.deepEqual(await preparePartnerDigiLockerSession({ db: s.db, request }), { ok: false, reason });
    assert.equal(s.writes, 0);
  }
});
