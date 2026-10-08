const { onDocumentCreated, onDocumentUpdated } = require('firebase-functions/v2/firestore');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { defineSecret } = require('firebase-functions/params');
const { initializeApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { getMessaging } = require('firebase-admin/messaging');

initializeApp();
const db = getFirestore('firestore-db-2');
const RIDE_SEARCH_TIMEOUT_MS = 5 * 60 * 1000;

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
    expired: ['No drivers available', 'No driver accepted your request. Please try again.'],
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

exports.expireUnmatchedRideRequests = onSchedule('every 1 minutes', async () => {
  const cutoff = new Date(Date.now() - RIDE_SEARCH_TIMEOUT_MS);
  const pending = await db.collection('rideRequests')
    .where('status', '==', 'requested')
    .where('createdAt', '<=', cutoff)
    .get();

  await Promise.all(pending.docs.map(async (snapshot) => {
    await db.runTransaction(async (transaction) => {
      const fresh = await transaction.get(snapshot.ref);
      if (!fresh.exists) return;
      const ride = fresh.data();
      const createdAt = ride.createdAt?.toMillis?.();
      if (ride.status !== 'requested' || !createdAt ||
          createdAt > Date.now() - RIDE_SEARCH_TIMEOUT_MS) return;
      transaction.update(snapshot.ref, {
        status: 'expired',
        expiredAt: new Date(),
      });
    });
  }));
});

const routesApiKey = defineSecret('ROUTES_API_KEY');

exports.computeRideRoute = onCall({
  secrets: [routesApiKey],
  maxInstances: 10,
}, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Sign in to request a route.');
  }
  const coordinates = ['origin', 'destination'].map((name) => {
    const value = request.data?.[name];
    const latitude = Number(value?.latitude);
    const longitude = Number(value?.longitude);
    if (!Number.isFinite(latitude) || !Number.isFinite(longitude) ||
        Math.abs(latitude) > 90 || Math.abs(longitude) > 180) {
      throw new HttpsError('invalid-argument', 'Valid route coordinates are required.');
    }
    return { latitude, longitude };
  });
  const [origin, destination] = coordinates;
  const response = await fetch('https://routes.googleapis.com/directions/v2:computeRoutes', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'X-Goog-Api-Key': routesApiKey.value(),
      'X-Goog-FieldMask': 'routes.distanceMeters,routes.duration,routes.polyline.encodedPolyline',
    },
    body: JSON.stringify({
      origin: { location: { latLng: origin } },
      destination: { location: { latLng: destination } },
      travelMode: 'DRIVE',
      routingPreference: 'TRAFFIC_UNAWARE',
      polylineQuality: 'HIGH_QUALITY',
    }),
  });
  if (!response.ok) {
    throw new HttpsError('unavailable', 'Road routing is temporarily unavailable.');
  }
  const data = await response.json();
  const route = data.routes?.[0];
  if (!route || !Number.isFinite(route.distanceMeters) ||
      typeof route.polyline?.encodedPolyline !== 'string') {
    throw new HttpsError('not-found', 'No drivable route was found.');
  }
  return {
    distanceMeters: route.distanceMeters,
    durationSeconds: Math.round(parseFloat(route.duration || '0s')),
    encodedPolyline: route.polyline.encodedPolyline,
  };
});
