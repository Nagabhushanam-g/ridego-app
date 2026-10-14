'use strict';

// Inactive server-only attestation validation. Issuance must be restricted to a
// trusted backend identity; client security rules alone cannot constrain Admin SDK.
const SOURCES = new Set(['digilocker', 'authorized_government_registry']);
const TYPES = new Set(['registration_certificate', 'driving_licence']);
const ID = /^[A-Za-z0-9_-]{1,128}$/;

function validatePartnerEvidence(doc, {partnerUid, now}) {
  if (!doc || !doc.exists || !ID.test(partnerUid || '') ||
      !Number.isSafeInteger(now) || now < 0) return false;
  const get = field => doc.get(field);
  return get('partnerUid') === partnerUid &&
    get('verified') === true && get('revoked') === false &&
    SOURCES.has(get('source')) && TYPES.has(get('documentType')) &&
    typeof get('issuer') === 'string' && ID.test(get('issuer')) &&
    typeof get('sourceReference') === 'string' && ID.test(get('sourceReference')) &&
    Number.isSafeInteger(get('verifiedAtMs')) &&
    get('verifiedAtMs') > 0 && get('verifiedAtMs') <= now &&
    Number.isSafeInteger(get('expiresAtMs')) &&
    get('expiresAtMs') > now;
}

module.exports = {validatePartnerEvidence};
