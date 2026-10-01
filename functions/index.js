const { onDocumentUpdated } = require('firebase-functions/v2/firestore');
const { initializeApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { getMessaging } = require('firebase-admin/messaging');

initializeApp();
const db = getFirestore('firestore-db-2');

exports.notifyRideStatusChange = onDocumentUpdated({
  document: 'rideRequests/{rideId}',
  database: 'firestore-db-2',
}, async (event) => {
  const before = event.data.before.data();
  const after = event.data.after.data();
  if (!before || !after || before.status === after.status) return;

  const status = after.status;
  let title = '';
  let body = '';
  let targetUid = after.riderId;

  if (status === 'accepted') {
    title = 'Driver accepted your ride';
    body = 'Your RideGo driver has accepted the trip.';
  } else if (status === 'arrived') {
    title = 'Driver has arrived';
    body = 'Your RideGo driver has arrived at the pickup point.';
  } else if (status === 'started') {
    title = 'Trip started';
    body = 'Your RideGo trip has started.';
  } else if (status === 'completed') {
    title = 'Trip completed';
    body = 'Your RideGo trip is complete. Thank you for riding!';
  } else if (status === 'cancelled') {
    title = 'Ride cancelled';
    body = 'Your RideGo ride was cancelled.';
  } else {
    return;
  }

  if (!targetUid) return;

  const devices = await db.collection('users').doc(targetUid).collection('devices').get();
  const tokens = devices.docs.map((doc) => doc.get('token')).filter(Boolean);
  if (!tokens.length) return;

  await getMessaging().sendEachForMulticast({
    tokens,
    notification: { title, body },
    data: { rideId: event.params.rideId, status },
  });
});
