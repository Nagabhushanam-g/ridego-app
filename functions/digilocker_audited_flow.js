'use strict';

// Inactive server-only wrapper. Emits allowlisted audit events through an
// injected sink. Sink failures must not alter authorization outcomes.
// Do not inject a sink that logs raw request or callback payloads.
const { buildDigiLockerAuditEvent } = require('./digilocker_audit');
const { handlePartnerDigiLockerCallable } = require('./digilocker_callable_adapter');
const { processResolvedDigiLockerCallback } = require('./digilocker_resolved_callback');

async function emitAudit(audit, details) {
  if (typeof audit !== 'function') return;
  try { await audit(buildDigiLockerAuditEvent(details)); }
  catch (_) { /* Audit failures must not leak secrets or affect the response. */ }
}

async function auditedPartnerDigiLockerSession({ request, db, now = Date.now(), audit }) {
  const result = await handlePartnerDigiLockerCallable({ request, db, now });
  const uid = request?.auth?.uid;
  const safeUid = typeof uid === 'string' && /^[A-Za-z0-9_-]{1,128}$/.test(uid)
    ? uid : undefined;
  const reasons = {
    unauthenticated: 'unauthenticated',
    'invalid-argument': 'invalid_document_type',
    'permission-denied': 'not_partner',
    'resource-exhausted': 'rate_limited',
    internal: 'internal_error',
  };
  await emitAudit(audit, {
    event: result.ok ? 'session_created' : 'session_rejected',
    reason: result.ok ? undefined : (reasons[result.errorCode] || 'internal_error'),
    uid: safeUid, now,
  });
  return result;
}

async function auditedDigiLockerCallback({ query, db, now = Date.now(), audit }) {
  const result = await processResolvedDigiLockerCallback({ query, db, now });
  const event = result.ok
    ? (result.outcome === 'denied' ? 'callback_denied' : 'callback_authorized')
    : 'callback_rejected';
  await emitAudit(audit, {
    event,
    reason: result.ok ? undefined :
      (result.reason === 'invalid_or_expired_session'
        ? 'invalid_or_expired_session'
        : result.errorCode === 'internal' ? 'internal_error' : 'invalid_callback'),
    now,
  });
  return result;
}

module.exports = { auditedPartnerDigiLockerSession, auditedDigiLockerCallback };
