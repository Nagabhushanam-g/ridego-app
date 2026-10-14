'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {prepareAuthenticatedPartnerReview: review} = require('./partner_review_adapter');

const base = {
  request: {
    auth: {uid: 'reviewer-1'},
    data: {partnerUid: 'partner-1', status: 'approved', reasonCode: 'verification_complete'}
  },
  now: 1700000000000
};

function db({active = true, role = 'partner_reviewer', partnerRole = 'driver', throwError = false} = {}) {
  return {
    collection(name) {
      assert.ok(['partnerReviewers', 'profiles'].includes(name));
      return {
        doc(id) {
          return {
            async get() {
              if (throwError) throw new Error('secret connection detail');
              if (name === 'partnerReviewers') {
                assert.equal(id, 'reviewer-1');
                return {exists: true, get: key => ({active, role})[key]};
              }
              assert.equal(id, 'partner-1');
              return {exists: true, get: key => ({role: partnerRole})[key]};
            }
          };
        }
      };
    }
  };
}

test('authorized reviewer may prepare decision without writing', async () => {
  const result = await review({...base, db: db()});
  assert.equal(result.ok, true);
  assert.equal(result.record.status, 'approved');
});

test('rejects unauthenticated and client-forged reviewer authorization', async () => {
  assert.equal((await review({...base, request: {data: base.request.data}, db: db()})).errorCode, 'unauthenticated');
  for (const options of [{active: false}, {role: 'driver'}]) {
    const result = await review({...base, db: db(options), request: {
      ...base.request, data: {...base.request.data, reviewerAuthorized: true, role: 'partner_reviewer'}
    }});
    assert.equal(result.errorCode, 'permission-denied');
  }
});

test('rejects non-partner and invalid decision', async () => {
  assert.equal((await review({...base, db: db({partnerRole: 'rider'})})).errorCode, 'failed-precondition');
  assert.equal((await review({...base, db: db(), request: {
    ...base.request, data: {...base.request.data, status: 'verified'}
  }})).errorCode, 'invalid-argument');
});

test('does not expose database errors', async () => {
  assert.deepEqual(await review({...base, db: db({throwError: true})}), {
    ok: false, errorCode: 'internal'
  });
});
