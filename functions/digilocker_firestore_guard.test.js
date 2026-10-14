'use strict';

// Static guard for DigiLocker-only Firestore collections. This is deliberately
// conservative and complements (but does not replace) Emulator rules tests.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const rules = fs.readFileSync(path.join(__dirname, '..', 'firestore.rules'), 'utf8');
const collections = [
  'digilockerAuthorizationSessions',
  'digilockerPartnerRateLimits',
];

test('DigiLocker session and rate-limit records remain server-only', () => {
  // Explicit collection matches require a security review; none are needed
  // while the inactive integration uses Admin SDK and catch-all deny.
  for (const collection of collections) {
    assert.equal(rules.includes('match /' + collection + '/'), false,
      collection + ' has an explicit client-facing rule: review before activation');
  }
  assert.match(rules, /match\s+\/\{document=\*\*\}\s*\{\s*allow\s+read,\s*write:\s*if\s+false\s*;/,
    'Deny-by-default Firestore catch-all must remain present');
});
