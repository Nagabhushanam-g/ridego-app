'use strict';
const fs = require('node:fs');
const path = require('node:path');

function assessPublication({read, evidence = {}}) {
  const blockers = [];
  const privacy = read('website/privacy.html');
  const rider = read('rider/android/app/build.gradle.kts');
  const partner = read('driver/android/app/build.gradle.kts');
  if (/Draft privacy information|not the final privacy notice/i.test(privacy)) {
    blockers.push('Public privacy policy remains a draft');
  }
  if (evidence.publicDeletionUrlVerified !== true) blockers.push('Public account deletion URL unverified');
  if (evidence.inAppDeletionTested !== true) blockers.push('In-app account deletion untested');
  if (evidence.retentionPolicyApproved !== true) blockers.push('Data retention and deletion policy unapproved');
  if (evidence.twoDeviceAcceptancePassed !== true) blockers.push('Two-device acceptance not signed off');
  if (evidence.playSigningVerified !== true) blockers.push('Play App Signing and artifact certificates unverified');
  if (evidence.playDataSafetyReviewed !== true) blockers.push('Play Data safety disclosures unreviewed');
  if (evidence.partnerPackageIdentityApproved !== true &&
      partner.includes('com.example.ridego_driver')) {
    blockers.push('Partner application ID not approved for first Play upload');
  }
  if (!rider.includes('applicationId = "com.ridego.rider"')) {
    blockers.push('Rider application ID unexpectedly changed');
  }
  return {ready: blockers.length === 0, blockers};
}

if (require.main === module) {
  const root = path.resolve(__dirname, '..');
  const result = assessPublication({
    read: file => fs.readFileSync(path.join(root, file), 'utf8')
  });
  console.log('RideGo Play Store publication gate — evidence not supplied');
  result.blockers.forEach(reason => console.log('BLOCKED: ' + reason));
  console.log(result.ready ? 'READY' : 'NOT READY');
  if (process.argv.includes('--enforce') && !result.ready) process.exitCode = 1;
}
module.exports = {assessPublication};
