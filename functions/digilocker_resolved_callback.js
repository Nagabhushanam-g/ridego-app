'use strict';

// Internal-only OAuth callback coordinator. No HTTP route, token exchange,
// external provider access or production deployment is enabled.
const { parseDigiLockerCallback } = require('./digilocker_callback');
const { resolveDigiLockerCallbackSession } = require('./digilocker_callback_lookup');
const { consumeAuthorizationSession } = require('./digilocker_session');

async function processResolvedDigiLockerCallback({ query, db, now = Date.now() }) {
  const parsed = parseDigiLockerCallback(query);
  if (!parsed.ok) return { ok: false, reason: parsed.reason };
  const resolved = await resolveDigiLockerCallbackSession({ db, state: parsed.state });
  if (!resolved.ok) return { ok: false, reason: 'invalid_or_expired_session' };
  const consumed = await consumeAuthorizationSession({
    db, sessionRef: resolved.sessionRef, uid: resolved.uid,
    state: parsed.state, now,
  });
  if (!consumed) return { ok: false, reason: 'invalid_or_expired_session' };
  if (parsed.outcome === 'denied') return { ok: true, outcome: 'denied' };
  // Never log, store or return the authorization code to a mobile client.
  // This internal result is only for a future approved server-side exchange.
  return { ok: true, outcome: 'authorized', code: parsed.code };
}

module.exports = { processResolvedDigiLockerCallback };
