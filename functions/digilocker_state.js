'use strict';

// Preparation-only helpers. Not wired to an HTTP endpoint or deployed function.
// A caller MUST atomically mark a server-stored state as consumed before token exchange.
const crypto = require('node:crypto');

const STATE_TTL_MS = 10 * 60 * 1000;

function newAuthorizationState() {
  return crypto.randomBytes(32).toString('base64url');
}

function hashAuthorizationState(state) {
  if (typeof state !== 'string' || !/^[A-Za-z0-9_-]{43}$/.test(state)) {
    throw new Error('Invalid authorization state');
  }
  return crypto.createHash('sha256').update(state, 'utf8').digest('hex');
}

function validateAuthorizationCallback({ state, session, uid, now = Date.now() }) {
  if (!session || typeof uid !== 'string' || !uid ||
      session.uid !== uid || session.consumed === true ||
      !Number.isFinite(session.createdAtMs) ||
      !Number.isFinite(now) || now < session.createdAtMs ||
      now - session.createdAtMs >= STATE_TTL_MS ||
      typeof session.stateHash !== 'string' ||
      !/^[a-f0-9]{64}$/.test(session.stateHash)) {
    return false;
  }
  let actual;
  try { actual = hashAuthorizationState(state); } catch (_) { return false; }
  return crypto.timingSafeEqual(Buffer.from(actual, 'hex'), Buffer.from(session.stateHash, 'hex'));
}

module.exports = { STATE_TTL_MS, newAuthorizationState, hashAuthorizationState, validateAuthorizationCallback };
