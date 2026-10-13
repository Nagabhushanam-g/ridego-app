'use strict';

// Preparation-only callable handler. Intentionally NOT exported from index.js.
// The official Requester authorization URL must be configured and reviewed
// before any live function is enabled.
const { persistAuthorizationSession } = require('./digilocker_session_store');
const { reserveDigiLockerAttempt } = require('./digilocker_rate_limit');

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
  const quota = await reserveDigiLockerAttempt({ db, uid, now });
  if (!quota.allowed) return { ok: false, reason: quota.reason };
  // Store only server-controlled UID; never trust request.data.uid.
  const session = await persistAuthorizationSession({
    db, uid, documentType, now,
  });
  return { ok: true, ...session };
}

module.exports = { preparePartnerDigiLockerSession };
