'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {assessPublication} = require('./play-publication-gate.cjs');
const base = {
  'website/privacy.html': '<h1>Draft privacy information — review required</h1>',
  'rider/android/app/build.gradle.kts': 'applicationId = "com.ridego.rider"',
  'driver/android/app/build.gradle.kts': 'applicationId = "com.example.ridego_driver"'
};
const read = name => base[name];
test('publication remains blocked without verified evidence', () => {
  const result = assessPublication({read});
  assert.equal(result.ready, false);
  assert.ok(result.blockers.some(x => x.includes('privacy')));
  assert.ok(result.blockers.some(x => x.includes('deletion')));
  assert.ok(result.blockers.some(x => x.includes('Two-device')));
});
test('claims alone cannot override draft privacy policy', () => {
  const evidence = Object.fromEntries([
    'publicDeletionUrlVerified', 'inAppDeletionTested', 'retentionPolicyApproved',
    'twoDeviceAcceptancePassed', 'cashPaymentDeviceAcceptancePassed',
    'productionFirebaseConfigurationVerified', 'playAppAccessVerified',
    'playSigningVerified', 'playDataSafetyReviewed',
    'partnerPackageIdentityApproved'
  ].map(key => [key, true]));
  assert.equal(assessPublication({read, evidence}).ready, false);
  const approvedRead = name => name === 'website/privacy.html'
    ? '<h1>RideGo Privacy Policy</h1>' : read(name);
  assert.equal(assessPublication({read: approvedRead, evidence}).ready, true);
});


test('truthy strings and numeric values never count as verified publication evidence', () => {
  const approvedRead = name => name === 'website/privacy.html'
    ? '<h1>RideGo Privacy Policy</h1>' : read(name);
  const keys = [
    'publicDeletionUrlVerified', 'inAppDeletionTested', 'retentionPolicyApproved',
    'twoDeviceAcceptancePassed', 'cashPaymentDeviceAcceptancePassed',
    'productionFirebaseConfigurationVerified', 'playAppAccessVerified',
    'playSigningVerified', 'playDataSafetyReviewed',
    'partnerPackageIdentityApproved'
  ];
  const allTrue = Object.fromEntries(keys.map(key => [key, true]));
  for (const key of keys) {
    for (const value of ['true', 'approved', 1, {}, []]) {
      const evidence = {...allTrue, [key]: value};
      const result = assessPublication({read: approvedRead, evidence});
      assert.equal(result.ready, false, key + ' incorrectly accepted ' + String(value));
      assert.ok(result.blockers.length > 0);
    }
  }
});
