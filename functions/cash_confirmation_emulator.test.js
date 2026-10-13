'use strict';
const assert = require('node:assert/strict');
const { test } = require('node:test');
const { initializeApp, deleteApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { confirmCashPaymentTransaction } = require('./cash_confirmation_transaction');

test('two simultaneous cash confirmations create one receipt and one earnings record', async () => {
  if (!process.env.FIRESTORE_EMULATOR_HOST) throw Error('Firestore Emulator is required');
  const app = initializeApp({ projectId: 'ridego-cash-integrity-test' }, 'cash-integrity');
  const db = getFirestore(app, 'firestore-db-2');
  const rideId = 'concurrent-payment-test';
  const uid = 'partner-A';
  try {
    await db.collection('rideRequests').doc(rideId).set({
      driverId: uid, riderId: 'rider-A', paymentRequired: true,
      status: 'completed', fare: 50, paymentStatus: 'pending',
    });
    const results = await Promise.all([
      confirmCashPaymentTransaction(db, uid, rideId),
      confirmCashPaymentTransaction(db, uid, rideId),
    ]);
    assert.deepEqual(results.map(r => r.alreadyConfirmed).sort(), [false, true]);
    const [receipts, earnings, ride] = await Promise.all([
      db.collection('paymentReceipts').where('rideId', '==', rideId).get(),
      db.collection('partnerEarnings').where('rideId', '==', rideId).get(),
      db.collection('rideRequests').doc(rideId).get(),
    ]);
    assert.equal(receipts.size, 1);
    assert.equal(earnings.size, 1);
    assert.equal(earnings.docs[0].get('commissionPaise'), 500);
    assert.equal(earnings.docs[0].get('partnerNetPaise'), 4500);
    assert.equal(ride.get('paymentStatus'), 'paid');
  } finally {
    await Promise.all(['rideRequests', 'paymentReceipts', 'partnerEarnings'].map(
      name => db.collection(name).doc(rideId).delete()));
    await deleteApp(app);
  }
});
