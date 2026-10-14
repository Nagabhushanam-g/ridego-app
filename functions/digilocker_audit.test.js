'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { buildDigiLockerAuditEvent } = require('./digilocker_audit');

test('records allowlisted metadata without sensitive OAuth or document fields', () => {
  const record = buildDigiLockerAuditEvent({
    event: 'callback_rejected', reason: 'invalid_or_expired_session',
    uid: 'partner-123', now: 123456,
    state: 'secret-state', code: 'secret-code', accessToken: 'secret-token',
    licenceNumber: 'DL-SECRET', registrationNumber: 'RC-SECRET',
  });
  assert.deepEqual(Object.keys(record).sort(),
    ['component', 'event', 'ownerHash', 'reason', 'timestampMs'].sort());
  assert.equal(record.ownerHash.length, 64);
  for (const secret of ['partner-123', 'secret-state', 'secret-code',
    'secret-token', 'DL-SECRET', 'RC-SECRET']) {
    assert.equal(JSON.stringify(record).includes(secret), false);
  }
});

test('rejects unknown event names and free-text reasons', () => {
  assert.throws(() => buildDigiLockerAuditEvent({
    event: 'callback_authorized', reason: 'access_token=secret',
  }));
  assert.throws(() => buildDigiLockerAuditEvent({ event: 'debug_all_documents' }));
  assert.throws(() => buildDigiLockerAuditEvent({
    event: 'session_created', uid: 'not valid email@example.com',
  }));
});

test('same Partner UID produces stable audit correlation hash', () => {
  const a = buildDigiLockerAuditEvent({ event: 'session_created', uid: 'partner-123', now: 1 });
  const b = buildDigiLockerAuditEvent({ event: 'callback_denied', uid: 'partner-123', now: 2 });
  assert.equal(a.ownerHash, b.ownerHash);
});
