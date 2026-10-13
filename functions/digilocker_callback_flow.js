'use strict';

// Preparation-only callback coordinator. No public endpoint, token exchange,
// or DigiLocker API calls. uid must come from trusted server-side session
// ownership, never directly from callback query parameters.
const { parseDigiLockerCallback } = require('./digilocker_callback');
const { consumeAuthorizationSession } = require('./digilocker_session');

async function processDigiLockerCallback({ query, db, sessionRef, uid, now = Date.now() }) {
  const parsed = parseDigiLockerCallback(query);
  if (!parsed.ok) return { ok: false, reason: parsed.reason };

  const consumed = await consumeAuthorizationSession({
    db, sessionRef, uid, state: parsed.state, now,
  });
  if (!consumed) return { ok: false, reason: 'invalid_or_expired_session' };

  if (parsed.outcome === 'denied') {
    return { ok: true, outcome: 'denied' };
  }
  // Do not log or persist this code. Exchange it server-side only after
  // Requester approval, provider configuration and full endpoint security review.
  return { ok: true, outcome: 'authorized', code: parsed.code };
}

module.exports = { processDigiLockerCallback };
