'use strict';

// Future endpoint helper: translate internal failures to a fixed safe response.
// Never reflect exception messages, provider payloads or OAuth credentials.
const CODES = new Set([
  'unauthenticated', 'invalid-argument', 'permission-denied',
  'resource-exhausted', 'failed-precondition', 'unavailable', 'internal',
]);

function safeDigiLockerError(error) {
  const code = error && typeof error === 'object' && error.code;
  if (typeof code === 'string' && CODES.has(code)) {
    return { ok: false, errorCode: code };
  }
  return { ok: false, errorCode: 'internal' };
}

module.exports = { safeDigiLockerError };
