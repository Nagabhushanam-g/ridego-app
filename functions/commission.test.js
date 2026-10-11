'use strict';
const assert = require('node:assert/strict');
const { test } = require('node:test');
const { calculateCashEarnings } = require('./commission');

test('₹100 fare splits into ₹10 commission and ₹90 Partner net', () => {
  assert.deepEqual(calculateCashEarnings(100), {
    grossPaise: 10000, commissionBasisPoints: 1000,
    commissionPaise: 1000, partnerNetPaise: 9000,
  });
});

test('₹74 cash fare splits into ₹7.40 commission and ₹66.60 net', () => {
  const result = calculateCashEarnings(74);
  assert.equal(result.commissionPaise, 740);
  assert.equal(result.partnerNetPaise, 6660);
  assert.equal(result.commissionPaise + result.partnerNetPaise, result.grossPaise);
});

test('₹1 fare preserves exact integer paise accounting', () => {
  const result = calculateCashEarnings(1);
  assert.equal(result.commissionPaise, 10);
  assert.equal(result.partnerNetPaise, 90);
});

test('reject invalid, fractional, negative and unsafe fares', () => {
  for (const fare of [0, -1, 10.5, NaN, Infinity, '100', Number.MAX_SAFE_INTEGER]) {
    assert.throws(() => calculateCashEarnings(fare), RangeError);
  }
});
