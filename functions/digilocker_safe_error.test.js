'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { safeDigiLockerError } = require('./digilocker_safe_error');

test('never exposes exception messages or provider payloads', () => {
  const error = new Error('access_token=secret-token; code=secret-code');
  error.providerResponse = { documentNumber: 'DL-SECRET' };
  assert.deepEqual(safeDigiLockerError(error), { ok: false, errorCode: 'internal' });
  assert.equal(JSON.stringify(safeDigiLockerError(error)).includes('secret'), false);
});

test('only known fixed error codes are returned', () => {
  assert.deepEqual(safeDigiLockerError({ code: 'unavailable', message: 'secret' }),
    { ok: false, errorCode: 'unavailable' });
  assert.deepEqual(safeDigiLockerError({ code: 'attacker-controlled', message: 'secret' }),
    { ok: false, errorCode: 'internal' });
  assert.deepEqual(safeDigiLockerError(null), { ok: false, errorCode: 'internal' });
});
