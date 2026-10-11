'use strict';

// Integer paise accounting. Policy v1: 10% (1,000 basis points).
const COMMISSION_BASIS_POINTS = 1000;

function calculateCashEarnings(fareRupees) {
  if (!Number.isSafeInteger(fareRupees) || fareRupees <= 0 ||
      !Number.isSafeInteger(fareRupees * 100)) {
    throw new RangeError('A positive whole-rupee fare within safe accounting limits is required.');
  }
  const grossPaise = fareRupees * 100;
  // Multiply before dividing only while still inside JavaScript safe integer bounds.
  const commissionNumerator = grossPaise * COMMISSION_BASIS_POINTS;
  if (!Number.isSafeInteger(commissionNumerator)) {
    throw new RangeError('Fare exceeds safe commission calculation limits.');
  }
  const commissionPaise = Math.round(commissionNumerator / 10000);
  return {
    grossPaise,
    commissionBasisPoints: COMMISSION_BASIS_POINTS,
    commissionPaise,
    partnerNetPaise: grossPaise - commissionPaise,
  };
}

module.exports = { COMMISSION_BASIS_POINTS, calculateCashEarnings };
