'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { validateCashConfirmation } = require('./cash_confirmation_policy');
const { calculateCashEarnings } = require('./commission');

const uid = 'partner-regression';
const rideId = 'ride-regression';
const ride = { driverId: uid, paymentRequired: true, status: 'completed',
  fare: 419, paymentStatus: 'pending', paymentMethod: 'cash' };

test('tested ₹419 cash ride retains exact 10% commission accounting', () => {
  assert.deepEqual(calculateCashEarnings(419), {
    grossPaise: 41900,
    commissionBasisPoints: 1000,
    commissionPaise: 4190,
    partnerNetPaise: 37710,
  });
  assert.deepEqual(validateCashConfirmation({ ride, uid, rideId, receipt: null }),
    { alreadyConfirmed: false, amount: 419 });
});

test('cash confirmation replay is idempotent and preserves the receipt', () => {
  const receipt = { driverId: uid, method: 'cash', status: 'paid', amount: 419 };
  const result = validateCashConfirmation({ ride, uid, rideId, receipt });
  assert.equal(result.alreadyConfirmed, true);
  assert.equal(result.response.amount, 419);
  assert.equal(result.response.alreadyConfirmed, true);
});

test('historical rides, unpaid trips and UPI selections cannot be cash-confirmed', () => {
  const cases = [
    [{ ...ride, paymentRequired: false }, 'failed-precondition'],
    [{ ...ride, status: 'started' }, 'failed-precondition'],
    [{ ...ride, paymentMethod: 'upi' }, 'failed-precondition'],
  ];
  for (const [candidate, expectedCode] of cases) {
    assert.throws(
      () => validateCashConfirmation({ ride: candidate, uid, rideId, receipt: null }),
      err => err.code === expectedCode,
    );
  }
});

test('other Partner cannot confirm another Partner’s completed cash trip', () => {
  assert.throws(
    () => validateCashConfirmation({ ride, uid: 'another-partner', rideId, receipt: null }),
    err => err.code === 'permission-denied',
  );
});
