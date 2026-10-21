'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {readFileSync} = require('node:fs');
const path = require('node:path');
const root = path.join(__dirname, '..');
const read = p => readFileSync(path.join(root, p), 'utf8');

// Safety invariant for the preparation phase. Remove only in a coordinated,
// explicitly approved release with complete server-side presence/dispatch gates.
test('inactive Partner verification and dispatch helpers are not deployed exports', () => {
  const index = read('functions/index.js');
  const forbidden = [
    'partner_online_transaction',
    'partner_online_grant_check',
    'partner_dispatch_transaction',
    'partner_active_ride_release',
    'partner_review_recheck',
    'digilocker_callable_adapter',
    'digilocker_callback_flow'
  ];
  for (const moduleName of forbidden) {
    assert.ok(!index.includes(moduleName),
      moduleName + ' unexpectedly referenced by deployed functions/index.js');
  }
});

test('server-only authorization, ride locks and evidence collections deny all client access', () => {
  const rules = read('firestore.rules');
  for (const collection of [
    'partnerOnlineAuthorizations', 'partnerActiveRideLocks',
    'partnerReviewEvidence', 'partnerReviewAudit'
  ]) {
    const escaped = collection.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    const block = rules.match(new RegExp('match /' + escaped + '/\\{[^}]+\\} \\{([^}]+)\\}'));
    assert.ok(block, 'missing explicit deny rule for ' + collection);
    assert.match(block[1], /allow read, write:\s*if false;/);
  }
});

test('current Partner app retains compatibility-only online write paths', () => {
  const driver = read('driver/lib/main.dart');
  assert.match(driver, /Future<void> _recordAvailability\(bool value\)/);
  assert.match(driver, /'isOnline': value/);
  assert.match(driver, /_restoreOnlinePreference\(\)/);
  assert.match(driver, /await _recordAvailability\(true\)/);
});
