'use strict';

// Callable boundary adapter, deliberately NOT exported from functions/index.js.
// A future Firebase onCall endpoint may invoke this only after explicit approval.
// No provider credentials, authorization URL or token exchange is present.
const { preparePartnerDigiLockerSession } = require('./digilocker_partner_session');

const REASONS = Object.freeze({
  unauthenticated: 'unauthenticated',
  invalid_document_type: 'invalid-argument',
  not_partner: 'permission-denied',
  cooldown: 'resource-exhausted',
  hourly_limit: 'resource-exhausted',
});

async function handlePartnerDigiLockerCallable({ request, db, now = Date.now() }) {
  if (!request || typeof request !== 'object' || !db) {
    return { ok: false, errorCode: 'invalid-argument' };
  }
  // Do not accept client-provided user IDs or timestamps. Only request.auth.uid.
  const result = await preparePartnerDigiLockerSession({ request, db, now });
  if (!result.ok) {
    return {
      ok: false,
      errorCode: REASONS[result.reason] || 'internal',
    };
  }
  // Never return stored state hashes or Firestore document contents.
  return {
    ok: true,
    state: result.state,
    sessionId: result.sessionId,
    expiresAtMs: result.expiresAtMs,
  };
}

module.exports = { handlePartnerDigiLockerCallable };
