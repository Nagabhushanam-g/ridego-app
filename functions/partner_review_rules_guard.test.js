'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {readFileSync} = require('node:fs');
const rules = readFileSync(require('node:path').join(__dirname, '..', 'firestore.rules'), 'utf8');

test('review evidence, reviewer roster and audit records explicitly deny all client access', () => {
  for (const collection of ['partnerReviewEvidence', 'partnerReviewers', 'partnerReviewAudit']) {
    const match = rules.match(new RegExp('match /' + collection + '/\\{[^}]+\\} \\{([^}]+)\\}'));
    assert.ok(match, 'missing explicit rules for ' + collection);
    assert.match(match[1], /allow read, write:\s*if false;/);
  }
});
