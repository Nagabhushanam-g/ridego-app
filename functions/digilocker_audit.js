'use strict';

// Safe, low-detail audit events for future server-side DigiLocker endpoints.
// Never include OAuth state, authorization codes, tokens, document contents,
// personal names, licence numbers or vehicle registration numbers.
const crypto = require('node:crypto');

const EVENTS = new Set([
  'session_created', 'session_rejected', 'callback_authorized',
  'callback_denied', 'callback_rejected', 'cleanup_completed',
]);
const REASONS = new Set([
  'unauthenticated', 'invalid_document_type', 'not_partner',
  'cooldown', 'hourly_limit', 'invalid_callback',
  'invalid_or_expired_session', 'internal_error',
]);

function buildDigiLockerAuditEvent({ event, reason, uid, now = Date.now() }) {
  if (!EVENTS.has(event) || !Number.isSafeInteger(now) || now < 0) {
    throw new Error('Invalid DigiLocker audit event');
  }
  const record = { component: 'digilocker', event, timestampMs: now };
  if (reason !== undefined) {
    if (!REASONS.has(reason)) throw new Error('Invalid DigiLocker audit reason');
    record.reason = reason;
  }
  // Hash the Partner UID for correlation without logging raw identifiers.
  // This is pseudonymous, not anonymous; access to audit logs must be limited.
  if (uid !== undefined) {
    if (typeof uid !== 'string' || !/^[A-Za-z0-9_-]{1,128}$/.test(uid)) {
      throw new Error('Invalid DigiLocker audit owner');
    }
    record.ownerHash = crypto.createHash('sha256').update(uid, 'utf8').digest('hex');
  }
  return record;
}

module.exports = { buildDigiLockerAuditEvent };
