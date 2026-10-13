'use strict';

// Preparation-only session cleanup. This module is NOT exported as a scheduled
// Cloud Function. Only the server may remove expired authorization sessions.
// No OAuth codes or provider tokens are stored here.
const { STATE_TTL_MS } = require('./digilocker_state');

async function deleteExpiredAuthorizationSessions({ db, now = Date.now(), limit = 100 }) {
  if (!db || typeof db.collection !== 'function' ||
      !Number.isSafeInteger(now) || now < 0 ||
      !Number.isInteger(limit) || limit < 1 || limit > 500) {
    throw new Error('Invalid cleanup arguments');
  }
  // Include legacy records without expiresAtMs by using createdAtMs.
  const cutoff = now - STATE_TTL_MS;
  const expired = await db.collection('digilockerAuthorizationSessions')
    .where('createdAtMs', '<=', cutoff)
    .orderBy('createdAtMs')
    .limit(limit)
    .get();
  if (expired.empty) return 0;
  const batch = db.batch();
  for (const doc of expired.docs) batch.delete(doc.ref);
  await batch.commit();
  return expired.size;
}

module.exports = { deleteExpiredAuthorizationSessions };
