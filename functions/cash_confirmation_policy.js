'use strict';
const { HttpsError } = require('firebase-functions/v2/https');

/** Pure validation of cash confirmation before transaction writes. */
function validateCashConfirmation({ ride, uid, rideId, receipt }) {
  if (ride.driverId !== uid) {
    throw new HttpsError('permission-denied', 'This ride belongs to another Partner.');
  }
  if (ride.paymentRequired !== true) {
    throw new HttpsError('failed-precondition', 'Historical rides are not eligible for cash collection.');
  }
  if (ride.status !== 'completed') {
    throw new HttpsError('failed-precondition', 'Complete the trip before collecting cash.');
  }
  const amount = ride.fare;
  if (!Number.isSafeInteger(amount) || amount <= 0) {
    throw new HttpsError('failed-precondition', 'The ride fare is invalid.');
  }
  if (receipt) {
    if (receipt.method !== 'cash' || receipt.status !== 'paid' ||
        receipt.driverId !== uid || receipt.amount !== amount) {
      throw new HttpsError('already-exists', 'A conflicting payment is already recorded.');
    }
    return { alreadyConfirmed: true, amount,
      response: { rideId, paymentStatus: 'paid', paymentMethod: 'cash',
        amount, currency: 'INR', receiptId: rideId, alreadyConfirmed: true } };
  }
  if (ride.paymentMethod && ride.paymentMethod !== 'cash') {
    throw new HttpsError('failed-precondition',
      'The rider selected another payment method. Cash confirmation is blocked.');
  }
  if (ride.paymentStatus && ride.paymentStatus !== 'pending') {
    throw new HttpsError('already-exists', 'This ride already has a payment.');
  }
  return { alreadyConfirmed: false, amount };
}

module.exports = { validateCashConfirmation };
