'use strict';

// Preparation-only callback input validation. This module does not exchange
// authorization codes, expose endpoints, or contact DigiLocker.
const MAX_CODE_LENGTH = 2048;
const MAX_ERROR_LENGTH = 128;

function parseDigiLockerCallback(query) {
  if (!query || typeof query !== 'object' || Array.isArray(query)) {
    return { ok: false, reason: 'invalid_query' };
  }
  const state = query.state;
  if (typeof state !== 'string' || !/^[A-Za-z0-9_-]{43}$/.test(state)) {
    return { ok: false, reason: 'invalid_state' };
  }
  const hasCode = Object.prototype.hasOwnProperty.call(query, 'code');
  const hasError = Object.prototype.hasOwnProperty.call(query, 'error');
  if (hasCode === hasError) return { ok: false, reason: 'invalid_result' };
  if (hasError) {
    if (typeof query.error !== 'string' ||
        !/^[A-Za-z0-9_.-]{1,128}$/.test(query.error)) {
      return { ok: false, reason: 'invalid_error' };
    }
    return { ok: true, outcome: 'denied', state, error: query.error };
  }
  if (typeof query.code !== 'string' ||
      query.code.length < 1 || query.code.length > MAX_CODE_LENGTH ||
      /[\x00-\x1f\x7f]/.test(query.code)) {
    return { ok: false, reason: 'invalid_code' };
  }
  return { ok: true, outcome: 'authorized', state, code: query.code };
}

module.exports = { parseDigiLockerCallback };
