import {readFileSync} from 'node:fs';
import {after, before, test} from 'node:test';
import assert from 'node:assert/strict';
import {initializeTestEnvironment, assertFails, assertSucceeds} from '@firebase/rules-unit-testing';
import {doc, setDoc, updateDoc, Timestamp, serverTimestamp} from 'firebase/firestore';

const databaseId = 'firestore-db-2';
let env;
const uid = 'partner-test-user';
const profile = {
  uid, role: 'driver', fullName: 'Test Partner',
  phone: '9999999999', vehicleType: 'Bike',
  vehicleNumber: 'TS09AB1234'
};
const partner = () => env.authenticatedContext(uid).firestore(databaseId);
const outsider = () => env.authenticatedContext('different-user').firestore(databaseId);
const ref = (db) => doc(db, 'profiles', uid);

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'ridego-security-test',
    firestore: {
      host: '127.0.0.1', port: 8080,
      rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8')
    }
  });
  await env.withSecurityRulesDisabled(async context => {
    await setDoc(ref(context.firestore(databaseId)), profile);
  });
});
after(async () => { if (env) await env.cleanup(); });

test('Partner may update ordinary personal and vehicle fields', async () => {
  await assertSucceeds(updateDoc(ref(partner()), {
    fullName: 'Updated Partner', vehicleModel: 'Sample Model',
    updatedAt: serverTimestamp()
  }));
});

test('Partner may save licence number and future expiry', async () => {
  await assertSucceeds(updateDoc(ref(partner()), {
    drivingLicenceNumber: 'TS1234567890',
    drivingLicenceExpiryDate: Timestamp.fromDate(new Date('2035-07-29T00:00:00Z')),
    drivingLicenceSubmittedAt: serverTimestamp()
  }));
});

test('Partner cannot grant approval', async () => {
  await assertFails(updateDoc(ref(partner()), {isApproved: true}));
  await assertFails(updateDoc(ref(partner()), {verificationStatus: 'approved'}));
  await assertFails(updateDoc(ref(partner()), {newUnknownApprovalFlag: true}));
});

test('Partner cannot change identity or role', async () => {
  await assertFails(updateDoc(ref(partner()), {role: 'admin'}));
  await assertFails(updateDoc(ref(partner()), {uid: 'someone-else'}));
});

test('Partner cannot submit invalid licence details', async () => {
  await assertFails(updateDoc(ref(partner()), {
    drivingLicenceNumber: 'bad!',
    drivingLicenceExpiryDate: Timestamp.fromDate(new Date('2035-07-29T00:00:00Z')),
    drivingLicenceSubmittedAt: serverTimestamp()
  }));
  await assertFails(updateDoc(ref(partner()), {
    drivingLicenceNumber: 'TS1234567890',
    drivingLicenceExpiryDate: Timestamp.fromDate(new Date('2020-01-01T00:00:00Z')),
    drivingLicenceSubmittedAt: serverTimestamp()
  }));
});

test('Other authenticated users cannot edit this Partner profile', async () => {
  await assertFails(updateDoc(ref(outsider()), {fullName: 'Impersonation'}));
});

test('New client profile cannot include an approval field', async () => {
  const db = env.authenticatedContext('new-partner').firestore(databaseId);
  await assertFails(setDoc(doc(db, 'profiles', 'new-partner'), {
    ...profile, uid: 'new-partner', isVerified: true
  }));
  await assertSucceeds(setDoc(doc(db, 'profiles', 'new-partner'), {
    ...profile, uid: 'new-partner'
  }));
});

test('Partner may read but never write backend verification records', async () => {
  const verification = {status: 'pending', method: 'digilocker', reviewed: false};
  await env.withSecurityRulesDisabled(async context => {
    await setDoc(doc(context.firestore(databaseId), 'partnerVerifications', uid), verification);
  });
  const {getDoc, deleteDoc} = await import('firebase/firestore');
  const ownerRef = doc(partner(), 'partnerVerifications', uid);
  await assertSucceeds(getDoc(ownerRef));
  await assertFails(updateDoc(ownerRef, {status: 'approved'}));
  await assertFails(deleteDoc(ownerRef));
  await assertFails(setDoc(doc(partner(), 'partnerVerifications', 'other-id'), verification));
  await assertFails(getDoc(doc(outsider(), 'partnerVerifications', uid)));
});


test('Clients cannot access DigiLocker sessions or rate limits', async () => {
  const {getDoc, deleteDoc} = await import('firebase/firestore');
  for (const collection of ['digilockerAuthorizationSessions', 'digilockerPartnerRateLimits']) {
    const id = collection === 'digilockerPartnerRateLimits' ? uid : 'session-test';
    const target = doc(partner(), collection, id);
    await assertFails(getDoc(target));
    await assertFails(setDoc(target, {uid, consumed: false}));
    await assertFails(updateDoc(target, {consumed: true}));
    await assertFails(deleteDoc(target));
    await assertFails(getDoc(doc(outsider(), collection, id)));
  }
});

test('Clients cannot set DigiLocker verification approval on their own profile', async () => {
  for (const field of ['digilockerVerified', 'rcVerified', 'drivingLicenceVerified', 'documentReviewStatus']) {
    await assertFails(updateDoc(ref(partner()), {[field]: true}));
  }
});

test('Partner and other clients cannot read or mutate review evidence, reviewer roster or audit', async () => {
  const {getDoc, deleteDoc} = await import('firebase/firestore');
  for (const collection of ['partnerReviewEvidence', 'partnerReviewers', 'partnerReviewAudit']) {
    const id = collection === 'partnerReviewers' ? uid : 'review-test';
    for (const db of [partner(), outsider()]) {
      const target = doc(db, collection, id);
      await assertFails(getDoc(target));
      await assertFails(setDoc(target, {partnerUid: uid, verified: true, active: true}));
      await assertFails(updateDoc(target, {verified: true}));
      await assertFails(deleteDoc(target));
    }
  }
});
