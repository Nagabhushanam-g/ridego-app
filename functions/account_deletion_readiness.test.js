'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {assessAccountDeletionReadiness} = require('./account_deletion_readiness');

function fixture({status = 'pending_review', uid = 'rider-1', activeDriver = false,
  activeRider = false, missing = false, failure = false} = {}) {
  return {collection(name) {
    if (name === 'accountDeletionRequests') return {doc() {
      return {async get() {
        if (failure) throw new Error('offline');
        return {exists: !missing, get: field => ({uid, status})[field]};
      }};
    }};
    return {where(field) {
      assert.ok(['driverId', 'riderId'].includes(field));
      return {where() {return {limit() {
        return {async get() {
          if (failure) throw new Error('offline');
          return {empty: !(field === 'driverId' ? activeDriver : activeRider)};
        }};
      }};}};
    }};
  }};
}

test('pending request with no active trip still requires retention review', async () => {
  assert.deepEqual(await assessAccountDeletionReadiness({
    db: fixture(), uid: 'rider-1'
  }), {ready: false, reason: 'retention_review_required', activeRideClear: true});
});

test('active rider and driver trips block processing', async () => {
  for (const options of [{activeDriver: true}, {activeRider: true}]) {
    assert.deepEqual(await assessAccountDeletionReadiness({
      db: fixture(options), uid: 'rider-1'
    }), {ready: false, reason: 'active_ride'});
  }
});

test('missing, completed or wrong-user requests never authorize processing', async () => {
  for (const options of [{missing: true}, {status: 'completed'}, {uid: 'other'}]) {
    assert.deepEqual(await assessAccountDeletionReadiness({
      db: fixture(options), uid: 'rider-1'
    }), {ready: false, reason: 'request_not_pending'});
  }
});

test('invalid inputs and database failures fail closed', async () => {
  assert.equal((await assessAccountDeletionReadiness({
    db: fixture(), uid: '../other'
  })).ready, false);
  assert.deepEqual(await assessAccountDeletionReadiness({
    db: fixture({failure: true}), uid: 'rider-1'
  }), {ready: false, reason: 'assessment_unavailable'});
});
