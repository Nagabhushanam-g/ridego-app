'use strict';
const assert = require('node:assert/strict');
const { test } = require('node:test');
const { validateCashConfirmation } = require('./cash_confirmation_policy');
const rideId = 'ride-123';
const uid = 'partner-A';
const base = { driverId: uid, paymentRequired: true, status: 'completed', fare: 50, paymentStatus: 'pending' };
const receipt = { method: 'cash', status: 'paid', driverId: uid, amount: 50 };
const validate = (ride = base, currentReceipt = null, actor = uid) =>
  validateCashConfirmation({ ride, uid: actor, rideId, receipt: currentReceipt });
const rejects = (code, ride, currentReceipt, actor) =>
  assert.throws(() => validate(ride, currentReceipt, actor), e => e.code === code);

test('new completed cash ride is eligible exactly once', () => {
  assert.deepEqual(validate(), { alreadyConfirmed: false, amount: 50 });
});
test('repeated confirmation returns same receipt without requesting writes', () => {
  assert.deepEqual(validate(base, receipt), {
    alreadyConfirmed: true, amount: 50,
    response: { rideId, paymentStatus: 'paid', paymentMethod: 'cash', amount: 50,
      currency: 'INR', receiptId: rideId, alreadyConfirmed: true },
  });
});
test('another Partner cannot confirm or replay the receipt', () => {
  rejects('permission-denied', base, null, 'partner-B');
  rejects('permission-denied', base, receipt, 'partner-B');
});
test('ride must be completed and explicitly payment-required', () => {
  rejects('failed-precondition', { ...base, status: 'started' });
  rejects('failed-precondition', { ...base, paymentRequired: false });
});
test('conflicting or mismatched receipt is rejected', () => {
  for (const mismatch of [{ method: 'upi' }, { status: 'pending' },
    { driverId: 'partner-B' }, { amount: 51 }]) {
    rejects('already-exists', base, { ...receipt, ...mismatch });
  }
});
test('cash cannot override another method or already-paid ride', () => {
  rejects('failed-precondition', { ...base, paymentMethod: 'upi' });
  rejects('already-exists', { ...base, paymentStatus: 'paid' });
});
test('invalid fare is blocked', () => {
  for (const fare of [0, -1, 2.5, '50', Number.MAX_SAFE_INTEGER + 1]) {
    rejects('failed-precondition', { ...base, fare });
  }
});
