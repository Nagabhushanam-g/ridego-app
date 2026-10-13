'use strict';
const { HttpsError } = require('firebase-functions/v2/https');
const { FieldValue } = require('firebase-admin/firestore');
const { calculateCashEarnings } = require('./commission');
const { validateCashConfirmation } = require('./cash_confirmation_policy');

async function confirmCashPaymentTransaction(db, uid, rideId) {
  const rideRef = db.collection('rideRequests').doc(rideId);
  const receiptRef = db.collection('paymentReceipts').doc(rideId);
  const earningsRef = db.collection('partnerEarnings').doc(rideId);
  return db.runTransaction(async (tx) => {
    const [rideSnap, receiptSnap] = await Promise.all([tx.get(rideRef), tx.get(receiptRef)]);
    if (!rideSnap.exists) throw new HttpsError('not-found', 'Ride not found.');
    const ride = rideSnap.data();
    const policy = validateCashConfirmation({
      ride, uid, rideId, receipt: receiptSnap.exists ? receiptSnap.data() : null,
    });
    if (policy.alreadyConfirmed) return policy.response;
    const amount = policy.amount;
    let earnings;
    try {
      earnings = calculateCashEarnings(amount);
    } catch (error) {
      throw new HttpsError('failed-precondition', 'The fare exceeds supported accounting limits.');
    }
    const { grossPaise, commissionBasisPoints, commissionPaise, partnerNetPaise } = earnings;
    const now = FieldValue.serverTimestamp();
    tx.create(receiptRef, {
      rideId, riderId: ride.riderId, driverId: uid,
      amount, currency: 'INR', method: 'cash', status: 'paid',
      collectedBy: uid, paidAt: now, createdAt: now,
    });
    tx.create(earningsRef, {
      rideId, driverId: uid, riderId: ride.riderId,
      currency: 'INR', paymentMethod: 'cash',
      grossPaise, commissionBasisPoints,
      commissionPaise, partnerNetPaise,
      settlementStatus: 'not_settled', createdAt: now,
    });
    tx.update(rideRef, {
      commissionBasisPoints, commissionPaise, partnerNetPaise,
      paymentMethod: 'cash', paymentStatus: 'paid',
      paidAt: now, paymentReceiptId: rideId,
    });
    return { rideId, paymentStatus: 'paid', paymentMethod: 'cash',
      amount, currency: 'INR', receiptId: rideId, alreadyConfirmed: false };
  });
}
module.exports = { confirmCashPaymentTransaction };
