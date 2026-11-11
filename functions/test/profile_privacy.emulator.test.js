'use strict';
const {test, before, after} = require('node:test');
const assert = require('node:assert/strict');
const {readFileSync} = require('node:fs');
const {resolve} = require('node:path');
const {initializeTestEnvironment, assertFails, assertSucceeds} = require('@firebase/rules-unit-testing');
const {doc, getDoc, getDocs, collection, setDoc, updateDoc, deleteDoc, query, where} = require('firebase/firestore');
const {initializeApp, deleteApp} = require('firebase-admin/app');
const {getFirestore} = require('firebase-admin/firestore');
const {prepare, syncReverseBlock} = require('../backfill_public_profiles');
const {testing: {syncProfile}} = require('../public_profiles');
const projectId = 'demo-tini-profile-privacy';
let env, adminApp, db;
const account = {uid: 'alice', fullName: 'Alice', username_lowercase: 'alice',
  email: 'private@example.com', phoneNumber: 'private', birthDate: '2000-01-01',
  fcmTokens: ['secret'], walletVersion: 2, tiniBalance: 321,
  throneReservedPoints: 123, boxReservedPoints: 45, walletDebt: 6,
  purchaseAccountToken: 'keep-this-token', badge: 'gold', blockedUsers: ['bob']};
before(async () => {
  const match = /^127\.0\.0\.1:(\d+)$/.exec(process.env.FIRESTORE_EMULATOR_HOST ?? '');
  if (!match) throw Error('Tests require a loopback Firestore emulator; never production');
  env = await initializeTestEnvironment({projectId, firestore: {
    host: '127.0.0.1', port: Number(match[1]),
    rules: readFileSync(resolve(__dirname, '../../firestore.rules'), 'utf8'),
  }});
  await env.clearFirestore();
  adminApp = initializeApp({projectId}, 'profile-privacy-tests');
  db = getFirestore(adminApp);
  await db.doc('users/alice').set(account);
  await db.doc('users/bob').set({uid: 'bob', username_lowercase: 'bob', tiniBalance: 9});
  await db.doc('users/alice/transactions/purchase').set({type: 'purchase', amount: 321});
  await db.doc('throne_data/current').set({currentBid: 123, leaderUid: 'alice'});
  await db.doc('box_holds/example').set({uid: 'alice', amount: 45, status: 'held'});
  await db.doc('wallet_config/runtime').set({version: 2, enabled: true});
});
after(async () => {
  if (env) await env.cleanup();
  if (adminApp) await deleteApp(adminApp);
});
test('read-only preparation does not publish profiles; apply preserves every account field and financial record', async () => {
  const paths = ['users/alice', 'users/bob', 'users/alice/transactions/purchase',
    'throne_data/current', 'box_holds/example', 'wallet_config/runtime'];
  const before = await Promise.all(paths.map(async p => (await db.doc(p).get()).data()));
  assert.equal((await prepare(db)).mode, 'read-only');
  assert.equal((await db.doc('public_profiles/alice').get()).exists, false);
  await prepare(db, {apply: true});
  await prepare(db, {apply: true});
  const after = await Promise.all(paths.map(async p => (await db.doc(p).get()).data()));
  assert.deepEqual(after, before);
  assert.equal((await db.doc('users/bob/blockedBy/alice').get()).exists, true);
  const audit = await prepare(db);
  assert.equal(audit.mismatches, 0);
  assert.equal(audit.missingReverseBlocks, 0);
});
test('owner can read full account; stranger and anonymous cannot get or list accounts', async () => {
  const own = env.authenticatedContext('alice').firestore();
  const other = env.authenticatedContext('bob').firestore();
  const anon = env.unauthenticatedContext().firestore();
  assert.equal((await assertSucceeds(getDoc(doc(own, 'users/alice')))).data().tiniBalance, 321);
  for (const client of [other, anon]) {
    await assertFails(getDoc(doc(client, 'users/alice')));
    await assertFails(getDocs(collection(client, 'users')));
  }
});
test('anonymous and signed-in profile searches work without leaking private fields', async () => {
  for (const client of [env.unauthenticatedContext().firestore(), env.authenticatedContext('bob').firestore()]) {
    const result = await assertSucceeds(getDocs(query(collection(client, 'public_profiles'), where('username_lowercase', '==', 'alice'))));
    assert.equal(result.size, 1);
    assert.deepEqual(result.docs[0].data(), {uid: 'alice', fullName: 'Alice', username_lowercase: 'alice', badge: 'gold'});
    for (const field of ['email', 'phoneNumber', 'birthDate', 'fcmTokens', 'walletVersion', 'tiniBalance',
      'throneReservedPoints', 'boxReservedPoints', 'walletDebt', 'purchaseAccountToken', 'blockedUsers']) {
      assert.equal(Object.hasOwn(result.docs[0].data(), field), false, field);
    }
  }
});
test('clients cannot publish profiles or change wallet fields; owners can still edit profile and contacts', async () => {
  const own = env.authenticatedContext('alice').firestore();
  const other = env.authenticatedContext('bob').firestore();
  await assertFails(setDoc(doc(own, 'public_profiles/alice'), {fullName: 'forged'}));
  await assertFails(deleteDoc(doc(other, 'public_profiles/alice')));
  for (const field of ['tiniBalance', 'throneReservedPoints', 'boxReservedPoints', 'walletDebt', 'purchaseAccountToken']) {
    await assertFails(updateDoc(doc(own, 'users/alice'), {[field]: field === 'purchaseAccountToken' ? 'forged' : 0}));
  }
  await assertFails(updateDoc(doc(other, 'users/alice'), {fullName: 'forged'}));
  await assertSucceeds(updateDoc(doc(own, 'users/alice'), {fullName: 'Updated', email: 'new-private@example.com'}));
  await syncProfile(db, 'alice');
  assert.equal((await getDoc(doc(other, 'public_profiles/alice'))).data().fullName, 'Updated');
  assert.equal((await db.doc('users/alice').get()).data().purchaseAccountToken, account.purchaseAccountToken);
});
test('private subcollections stay private and public relationship subcollections keep working', async () => {
  const own = env.authenticatedContext('alice').firestore();
  const other = env.authenticatedContext('bob').firestore();
  await assertSucceeds(getDocs(collection(own, 'users/alice/transactions')));
  await assertFails(getDocs(collection(other, 'users/alice/transactions')));
  await assertSucceeds(getDocs(collection(other, 'users/alice/followers')));
  await assertSucceeds(getDoc(doc(other, 'users/bob/blockedBy/alice')));
  await assertFails(getDocs(collection(own, 'users/bob/blockedBy')));
  await assertFails(deleteDoc(doc(own, 'users/alice'))); // nonzero balance/reservations
});
test('refresh removes stale private fields and presence opt-out; deleted source removes profile', async () => {
  await db.doc('public_profiles/alice').set({email: 'old-leak'}, {merge: true});
  await db.doc('users/alice').update({showActivityStatus: false, isOnline: true, lastSeen: 123});
  await syncProfile(db, 'alice');
  const profile = (await db.doc('public_profiles/alice').get()).data();
  assert.equal(Object.hasOwn(profile, 'email'), false);
  assert.equal(Object.hasOwn(profile, 'lastSeen'), false);
  assert.equal(Object.hasOwn(profile, 'isOnline'), false);
  await db.doc('users/bob').delete();
  await syncProfile(db, 'bob');
  await syncProfile(db, 'bob');
  assert.equal((await db.doc('public_profiles/bob').get()).exists, false);
});

test('backfill does not recreate a block removed after the scan, or use a deleted source', async () => {
  await db.doc('users/target').set({fullName: 'Target'});
  await db.doc('users/source').set({blockedUsers: []});
  await syncReverseBlock(db, 'source', 'target');
  assert.equal((await db.doc('users/target/blockedBy/source').get()).exists, false);
  await db.doc('users/source/blocked/target').set({uid: 'target'});
  await db.doc('users/source').delete();
  await syncReverseBlock(db, 'source', 'target');
  assert.equal((await db.doc('users/target/blockedBy/source').get()).exists, false);
});

test('new accounts can create their private profile but cannot mint a wallet or publish a profile', async () => {
  const owner = env.authenticatedContext('new-user').firestore();
  await assertSucceeds(setDoc(doc(owner, 'users/new-user'), {
    fullName: 'New User', email: 'private@example.com', fcmTokens: ['private'],
  }));
  await assertSucceeds(getDoc(doc(owner, 'users/new-user')));
  await assertFails(setDoc(doc(owner, 'public_profiles/new-user'), {fullName: 'New User'}));
  await assertFails(updateDoc(doc(owner, 'users/new-user'), {walletVersion: 2, tiniBalance: 1000}));
  await syncProfile(db, 'new-user');
  const guest = env.unauthenticatedContext().firestore();
  assert.deepEqual((await assertSucceeds(getDoc(doc(guest, 'public_profiles/new-user')))).data(),
    {uid: 'new-user', fullName: 'New User'});
  await assertFails(getDoc(doc(guest, 'users/new-user')));
});
