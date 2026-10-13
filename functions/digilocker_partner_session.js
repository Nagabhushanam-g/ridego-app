'use strict';

// Preparation-only callable handler. Intentionally NOT exported from index.js.
// The official Requester authorization URL must be configured and reviewed
// before any live function is enabled.
const { createRateLimitedDigiLockerSession } = require('./digilocker_atomic_session');

async function preparePartnerDigiLockerSession({ request, db, now = Date.now() }) {
  const uid = request?.auth?.uid;
  if (typeof uid !== 'string' || !uid) {
    return { ok: false, reason: 'unauthenticated' };
  }
  const documentType = request?.data?.documentType;
  if (documentType !== 'dl' && documentType !== 'rc') {
    return { ok: false, reason: 'invalid_document_type' };
  }
  const profile = await db.collection('profiles').doc(uid).get();
  if (!profile.exists || profile.get('role') !== 'driver') {
    return { ok: false, reason: 'not_partner' };
  }
  // Atomic quota + session write: failed commits consume no quota.
  return createRateLimitedDigiLockerSession({ db, uid, documentType, now });
}

module.exports = { preparePartnerDigiLockerSession };
