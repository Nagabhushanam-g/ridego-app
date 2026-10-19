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
  if (evidence.cashPaymentDeviceAcceptancePassed !== true) blockers.push('Cash receipt and commission device acceptance unverified');
  if (evidence.productionFirebaseConfigurationVerified !== true) blockers.push('Production Firebase rules, functions and database configuration unverified');
  if (evidence.playAppAccessVerified !== true) blockers.push('Play reviewer app access instructions unverified');
  if (evidence.playSigningVerified !== true) blockers.push('Play App Signing and artifact certificates unverified');
  if (evidence.playDataSafetyReviewed !== true) blockers.push('Play Data safety disclosures unreviewed');
  if (evidence.storeListingAssetsApproved !== true) blockers.push('Rider and Partner Play Store listings and assets unapproved');
  if (evidence.androidPermissionsReviewed !== true) blockers.push('Android permission declarations unreviewed');
  if (evidence.playInternalTrackAcceptancePassed !== true) blockers.push('Play internal-track installation and login acceptance unverified');
  // Explicit approval is required even if the Partner namespace changes.
  // A package rename must never silently bypass the first-upload decision.
  if (evidence.partnerPackageIdentityApproved !== true) {
    blockers.push('Partner application ID not approved for first Play upload');
  }
  const applicationIds = source => [...source.matchAll(/\bapplicationId\s*=\s*"([^"]+)"/g)]
    .map(match => match[1]);
  const riderIds = applicationIds(rider);
  const partnerIds = applicationIds(partner);
  if (riderIds.length !== 1 || riderIds[0] !== 'com.ridego.rider') {
    blockers.push('Rider application ID unexpectedly changed or is ambiguous');
  }
  if (partnerIds.length !== 1 ||
      !['com.example.ridego_driver', 'com.ridego.partner'].includes(partnerIds[0])) {
    blockers.push('Partner application ID unexpected or ambiguous; review Firebase and signing migration');
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
