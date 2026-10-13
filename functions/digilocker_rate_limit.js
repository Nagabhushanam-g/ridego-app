'use strict';

// Preparation-only transactional per-Partner rate limiter. Not deployed.
// Caller must supply Firebase-authenticated uid from trusted backend context.
// Each transaction reads and writes one stable Partner-specific counter doc.
const MIN_INTERVAL_MS = 60 * 1000;
const WINDOW_MS = 60 * 60 * 1000;
const MAX_ATTEMPTS_PER_WINDOW = 5;

async function reserveDigiLockerAttempt({ db, uid, now = Date.now() }) {
  if (!db || typeof db.runTransaction !== 'function' ||
      typeof uid !== 'string' || !/^[A-Za-z0-9_-]{1,128}$/.test(uid) ||
      !Number.isSafeInteger(now) || now < 0) {
    throw new Error('Invalid DigiLocker rate-limit request');
  }
  const ref = db.collection('digilockerPartnerRateLimits').doc(uid);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const prev = snap.exists ? snap.data() : null;
    const windowStart = Number.isSafeInteger(prev?.windowStartMs) ? prev.windowStartMs : now;
    const reset = now < windowStart || now - windowStart >= WINDOW_MS;
    const count = reset ? 0 : (Number.isSafeInteger(prev?.count) ? prev.count : MAX_ATTEMPTS_PER_WINDOW);
    const lastAttemptMs = reset ? null : prev?.lastAttemptMs;
    if (lastAttemptMs != null && (!Number.isSafeInteger(lastAttemptMs) ||
        now - lastAttemptMs < MIN_INTERVAL_MS)) {
      return { allowed: false, reason: 'cooldown' };
    }
    if (count >= MAX_ATTEMPTS_PER_WINDOW) {
      return { allowed: false, reason: 'hourly_limit' };
    }
    tx.set(ref, {
      windowStartMs: reset ? now : windowStart,
      lastAttemptMs: now,
      count: count + 1,
    });
    return { allowed: true };
  });
}

module.exports = { reserveDigiLockerAttempt, MIN_INTERVAL_MS, WINDOW_MS, MAX_ATTEMPTS_PER_WINDOW };
