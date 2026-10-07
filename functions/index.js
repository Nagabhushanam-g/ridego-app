const { onDocumentCreated, onDocumentUpdated } = require('firebase-functions/v2/firestore');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const { initializeApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { getMessaging } = require('firebase-admin/messaging');

initializeApp();
const db = getFirestore('firestore-db-2');

async function sendToUser(uid, title, body, rideId, status) {
  if (!uid) return;
  const devices = await db.collection('users').doc(uid).collection('devices').get();
  const tokens = devices.docs.map((doc) => doc.get('token')).filter(Boolean);
  if (!tokens.length) return;
  await getMessaging().sendEachForMulticast({
    tokens,
    notification: { title, body },
    data: { rideId, status },
  });
}

exports.notifyRideCreated = onDocumentCreated({
  document: 'rideRequests/{rideId}',
  database: 'firestore-db-2',
}, async (event) => {
  const ride = event.data.data();
  if (!ride) return;
  const drivers = await db.collection('profiles').where('role', '==', 'driver').get();
  await Promise.all(drivers.docs.map((driver) => sendToUser(
    driver.id,
    'New Ride Request',
    `${ride.vehicle || 'Ride'} request • ₹${ride.fare || 0}`,
    event.params.rideId,
    'requested',
  )));
});

exports.notifyRideStatusChange = onDocumentUpdated({
  document: 'rideRequests/{rideId}',
  database: 'firestore-db-2',
}, async (event) => {
  const before = event.data.before.data();
  const after = event.data.after.data();
  if (!before || !after || before.status === after.status) return;

  const status = after.status;
  const messages = {
    accepted: ['Driver accepted your ride', 'Your RideGo driver has accepted the trip.'],
    arrived: ['Driver has arrived', 'Your RideGo driver has arrived at the pickup point.'],
    started: ['Trip started', 'Your RideGo trip has started.'],
    completed: ['Trip completed', 'Your RideGo trip is complete. Thank you for riding!'],
    cancelled: ['Ride cancelled', 'Your RideGo ride was cancelled.'],
  };
  const message = messages[status];
  if (!message) return;

  await sendToUser(
    after.riderId,
    message[0],
    message[1],
    event.params.rideId,
    status,
  );
});


const RIDE_SEARCH_TIMEOUT_MS = 5 * 60 * 1000;

exports.expireUnmatchedRideRequests = onSchedule({
  schedule: 'every 1 minutes',
  timeZone: 'UTC',
}, async () => {
  const cutoff = new Date(Date.now() - RIDE_SEARCH_TIMEOUT_MS);
  const snapshot = await db.collection('rideRequests')
    .where('status', '==', 'requested')
    .where('createdAt', '<=', cutoff)
    .get();

  if (snapshot.empty) return;

  await Promise.all(snapshot.docs.map(async (doc) => {
    await db.runTransaction(async (transaction) => {
      const fresh = await transaction.get(doc.ref);
      if (!fresh.exists) return;

      const ride = fresh.data();
      if (ride.status !== 'requested' || ride.driverId) return;

      transaction.update(doc.ref, {
        status: 'expired',
        expiredAt: new Date(),
        expiryReason: 'no_driver_available',
      });
    });
  }));
});
