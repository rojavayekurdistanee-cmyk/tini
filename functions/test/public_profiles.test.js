'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {testing: {projectProfile, syncProfile, PUBLIC_FIELDS}} = require('../public_profiles');

test('public projection uses an allowlist and excludes all sensitive account data', () => {
  const account = {uid: 'wrong', fullName: 'Example', username_lowercase: 'example',
    email: 'private@example.com', phone: 'private', phoneNumber: 'private',
    birthDate: '2000-01-01', dob: 'private', fcmTokens: ['secret'],
    tiniBalance: 350, throneReservedPoints: 50, boxReservedPoints: 25,
    walletVersion: 2, walletDebt: 10, purchaseAccountToken: 'secret',
    twoFactorEnabled: true, passkeyEnabled: true, blockedUsers: ['other'],
    recentSearches: ['private'], futurePrivateField: 'secret',
    audience_18plus: true, crownNumber: 'Tini-12345', badge: 'gold'};
  const result = projectProfile('alice', account);
  assert.deepEqual(result, {uid: 'alice', fullName: 'Example', username_lowercase: 'example',
    crownNumber: 'Tini-12345', badge: 'gold', audience_18plus: true});
  assert.equal(PUBLIC_FIELDS.includes('tiniBalance'), false);
});
test('activity opt-out removes online status and timestamps', () => {
  assert.deepEqual(projectProfile('alice', {showActivityStatus: false, isOnline: true, lastSeen: 123}),
    {uid: 'alice', showActivityStatus: false});
  assert.equal(projectProfile('alice', {isOnline: true}).isOnline, true);
});
function fake(source, current) {
  const writes = [];
  const db = {doc: path => ({path}), runTransaction: callback => callback({
    get: async ref => ref.path.startsWith('users/')
      ? {exists: !!source, data: () => source}
      : {exists: !!current, data: () => current},
    set: (ref, data) => writes.push(['set', ref.path, data]),
    delete: ref => writes.push(['delete', ref.path]),
  })};
  return {db, writes};
}
test('sync reads current source and replaces stale fields instead of merging', async () => {
  const {db, writes} = fake({fullName: 'Latest', tiniBalance: 123}, {uid: 'alice', fullName: 'Old', email: 'leaked'});
  await syncProfile(db, 'alice');
  assert.deepEqual(writes, [['set', 'public_profiles/alice', {uid: 'alice', fullName: 'Latest'}]]);
});
test('wallet-only changes do not write the public projection', async () => {
  const {db, writes} = fake({fullName: 'Latest', tiniBalance: 999}, {uid: 'alice', fullName: 'Latest'});
  await syncProfile(db, 'alice');
  assert.deepEqual(writes, []);
});
test('deletion/retry cannot resurrect a profile or write the wallet', async () => {
  const {db, writes} = fake(null, {uid: 'alice'});
  await syncProfile(db, 'alice');
  assert.deepEqual(writes, [['delete', 'public_profiles/alice']]);
  const retry = fake(null, null);
  await syncProfile(retry.db, 'alice');
  assert.deepEqual(retry.writes, []);
});
