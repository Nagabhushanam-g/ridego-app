'use strict';

// Atomic Partner quota reservation + session creation, preparation only.
// This prevents failed session writes from consuming a Partner's quota.
const { createAuthorizationSession } = require('./digilocker_session_create');
const { MIN_INTERVAL_MS, WINDOW_MS, MAX_ATTEMPTS_PER_WINDOW } = require('./digilocker_rate_limit');

async function createRateLimitedDigiLockerSession({ db, uid, documentType, now = Date.now() }) {
  if (!db || typeof db.runTransaction !== 'function' ||
      typeof uid !== 'string' || !/^[A-Za-z0-9_-]{1,128}$/.test(uid)) {
    throw new Error('Invalid DigiLocker session request');
  }
  // Validate all request fields before reading or writing Firestore.
  const session = createAuthorizationSession({ uid, documentType, now });
  const rateRef = db.collection('digilockerPartnerRateLimits').doc(uid);
  const sessionRef = db.collection('digilockerAuthorizationSessions').doc(session.sessionId);
  const outcome = await db.runTransaction(async (tx) => {
    const snap = await tx.get(rateRef);
    const prev = snap.exists ? snap.data() : null;
    const windowStart = Number.isSafeInteger(prev?.windowStartMs) ? prev.windowStartMs : now;
    const reset = !prev || now < windowStart || now - windowStart >= WINDOW_MS;
    const count = reset ? 0 : (Number.isSafeInteger(prev?.count) ? prev.count : MAX_ATTEMPTS_PER_WINDOW);
    const lastAttemptMs = reset ? null : prev?.lastAttemptMs;
    if (lastAttemptMs != null && (!Number.isSafeInteger(lastAttemptMs) ||
        now - lastAttemptMs < MIN_INTERVAL_MS)) {
      return { ok: false, reason: 'cooldown' };
    }
    if (count >= MAX_ATTEMPTS_PER_WINDOW) return { ok: false, reason: 'hourly_limit' };
    tx.create(sessionRef, session.record);
    tx.set(rateRef, {
      windowStartMs: reset ? now : windowStart,
      lastAttemptMs: now,
      count: count + 1,
    });
    return { ok: true };
  });
  if (!outcome.ok) return outcome;
  return {
    ok: true, state: session.state,
    sessionId: session.sessionId, expiresAtMs: session.record.expiresAtMs,
  };
}

module.exports = { createRateLimitedDigiLockerSession };
