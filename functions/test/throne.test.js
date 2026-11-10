'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {createRequire} = require('node:module');
const runtimeRequire = createRequire(require.resolve('../throne-v2/index.js'));
const {initializeApp} = runtimeRequire('firebase-admin/app');
const {getFirestore, Timestamp} = runtimeRequire('firebase-admin/firestore');
const projectId = process.env.GCLOUD_PROJECT || 'demo-tini-throne';
if (!projectId.startsWith('demo-') || !/^127\.0\.0\.1:\d+$/.test(process.env.FIRESTORE_EMULATOR_HOST || ''))
  throw new Error('Tests require a loopback emulator and demo-* project; production is forbidden.');
initializeApp({projectId});
const db = getFirestore();
const throne = require('../throne-v2/throne');
const {bid, advance, auction, react, DAY} = throne.testing;
const now = 1800000000000;
const host = `http://${process.env.FIRESTORE_EMULATOR_HOST}`;
const root = `${host}/v1/projects/${projectId}/databases/(default)/documents`;
async function read(path) { return (await db.doc(path).get()).data(); }
async function seed(options = {}) {
  const response = await fetch(`${host}/emulator/v1/projects/${projectId}/databases/(default)/documents`, {method: 'DELETE'});
  assert.equal(response.ok, true);
  await db.doc('throne_config/runtime').set({enabled: true, financialSafetyVersion: 2});
  await db.doc('throne_data/current').set(auction('auction-1', now));
  for (const uid of ['alice', 'bob', 'carol'])
    await db.doc(`users/${uid}`).set({titiBalance: options.balance ?? 20000, fullName: uid, profileImg: ''});
}
const offer = (uid, amount, requestId = `${uid}-${amount}`, auctionId = 'auction-1', clock = () => now + 1) =>
  bid(db, uid, {amount, requestId, auctionId}, clock);
const rejectsCode = (promise, code) => assert.rejects(promise, e => e.code === code);

test('reserve, self-raise difference, refund, immutable deadline and financial conservation', async () => {
  await seed();
  await offer('alice', 3000);
  assert.equal((await read('users/alice')).titiBalance, 17000);
  await offer('alice', 5000);
  assert.equal((await read('users/alice')).titiBalance, 15000);
  assert.equal((await read('users/alice')).throneReservedPoints, 5000);
  await offer('bob', 6000);
  assert.equal((await read('users/alice')).titiBalance, 20000);
  assert.equal((await read('users/alice')).throneReservedPoints, 0);
  assert.equal((await read('users/bob')).titiBalance, 14000);
  const state = await read('throne_data/current');
  assert.equal(state.kingUid, null);
  assert.equal(state.auctionEndsAt.toMillis(), now + DAY);
  assert.equal(state.leaderUid, 'bob');
  assert.equal((await db.collection('throne_ledger').get()).size, 4);
});

test('lost response/replay cannot double charge or refund; request payload is bound', async () => {
  await seed();
  const first = await offer('alice', 3000, 'lost-response');
  await offer('bob', 4000);
  assert.deepEqual(await offer('alice', 3000, 'lost-response'), first);
  assert.equal((await read('users/alice')).titiBalance, 20000);
  assert.equal((await db.collection('throne_ledger').get()).size, 3);
  await rejectsCode(offer('alice', 5000, 'lost-response'), 'already-exists');
});

test('bid validations: insufficient amount, balance, cap, malformed input and stale auction', async () => {
  await seed({balance: 500});
  await rejectsCode(offer('alice', 501), 'resource-exhausted');
  for (const value of [0, -1, 10001, 1.5, '100', null])
    await rejectsCode(offer('alice', value, 'bad-input'), 'invalid-argument');
  await offer('alice', 300);
  await rejectsCode(offer('bob', 300), 'out-of-range');
  await rejectsCode(offer('bob', 400, 'stale', 'old-auction'), 'failed-precondition');
  await rejectsCode(offer('alice', 400, '../bad-id'), 'invalid-argument');
  assert.equal((await read('users/alice')).titiBalance, 200);
});

test('concurrent bids and duplicate submissions preserve one escrow and no negative balance', async () => {
  await seed({balance: 5000});
  await Promise.allSettled([offer('alice', 3000), offer('bob', 4000), offer('bob', 4000)]);
  const state = await read('throne_data/current');
  assert.equal(state.leaderUid, 'bob');
  const a = await read('users/alice'); const b = await read('users/bob');
  assert.equal(a.titiBalance, 5000); assert.equal(b.titiBalance, 1000);
  assert.equal(b.throneReservedPoints, 4000);
  assert.equal(a.titiBalance + b.titiBalance + b.throneReservedPoints, 10000);
});

test('normal settlement is idempotent, full 24-hour reign begins at actual server coronation', async () => {
  await seed(); await offer('alice', 3000);
  const late = now + DAY + 90000;
  await Promise.all([advance(db, () => late), advance(db, () => late)]);
  const state = await read('throne_data/current');
  assert.equal(state.status, 'reign'); assert.equal(state.kingUid, 'alice');
  assert.equal(state.reignStartsAt.toMillis(), late);
  assert.equal(state.lockEndTime.toMillis(), late + DAY);
  assert.equal((await read('users/alice')).titiBalance, 17000);
  assert.equal((await read('users/alice')).throneReservedPoints, 0);
  assert.equal((await db.collection('throne_reigns').get()).size, 1);
  await rejectsCode(offer('bob', 4000), 'failed-precondition');
  await advance(db, () => late + DAY);
  const next = await read('throne_data/current');
  assert.equal(next.status, 'auction'); assert.notEqual(next.auctionId, state.auctionId);
  assert.equal((await read('throne_entitlements/alice')).formerKing, true);
  assert.equal((await read('throne_reigns/auction-1')).completed, true);
  await advance(db, () => late + DAY);
  assert.equal((await read('throne_data/current')).auctionId, next.auctionId);
});

test('10,000 instant victory lasts exactly seven days, retries and former king return', async () => {
  await seed();
  await offer('bob', 5000);
  const result = await offer('alice', 10000, 'instant');
  const state = await read('throne_data/current');
  assert.equal(state.status, 'reign'); assert.equal(state.lockEndTime.toMillis() - state.reignStartsAt.toMillis(), 7 * DAY);
  assert.equal((await read('users/bob')).titiBalance, 20000);
  assert.deepEqual(await offer('alice', 10000, 'instant'), result);
  assert.equal((await read('users/alice')).titiBalance, 10000);
  await advance(db, () => now + 1 + 7 * DAY);
  const next = await read('throne_data/current');
  await offer('alice', 10000, 'again', next.auctionId, () => now + 2 + 7 * DAY);
  const entitlement = await read('throne_entitlements/alice');
  assert.equal(entitlement.coronationCount, 2); assert.equal(entitlement.formerKing, true);
  assert.equal((await db.collection('throne_reigns').get()).size, 2);
});

test('deadline rejects arriving bids; empty auctions advance once without a phantom king', async () => {
  await seed();
  await rejectsCode(offer('alice', 100, 'late', 'auction-1', () => now + DAY), 'deadline-exceeded');
  await Promise.all([advance(db, () => now + DAY), advance(db, () => now + DAY)]);
  const state = await read('throne_data/current');
  assert.notEqual(state.auctionId, 'auction-1'); assert.equal(state.kingUid, null);
  assert.equal((await db.collection('throne_reigns').get()).size, 0);
  assert.equal((await read('users/alice')).titiBalance, 20000);
});

test('settlement racing an instant bid cannot create two kings', async () => {
  await seed(); await offer('bob', 100);
  await Promise.allSettled([advance(db, () => now + DAY),
    offer('alice', 10000, 'racing', 'auction-1', () => now + DAY)]);
  assert.equal((await db.collection('throne_reigns').get()).size, 1);
  assert.equal((await read('throne_data/current')).kingUid, 'bob');
});

test('one immutable spectator reaction per user per reign; no points awarded', async () => {
  await seed(); await offer('alice', 10000);
  await Promise.all([react(db, 'bob', {coronationId: 'auction-1', kind: 'heart'}, () => now + 2),
    react(db, 'bob', {coronationId: 'auction-1', kind: 'heart'}, () => now + 2)]);
  await react(db, 'bob', {coronationId: 'auction-1', kind: 'fire'}, () => now + 3);
  assert.deepEqual((await read('throne_data/current')).reactions, {crown: 0, heart: 1, fire: 0});
  assert.equal((await read('users/bob')).titiBalance, 20000);
  await rejectsCode(react(db, 'bob', {coronationId: 'auction-1', kind: 'heart'}, () => now + 8 * DAY), 'failed-precondition');
});

test('disabled financial activation and legacy state fail closed without guessing refunds', async () => {
  await seed();
  await db.doc('throne_config/runtime').delete();
  await rejectsCode(offer('alice', 100), 'failed-precondition');
  await db.doc('throne_data/current').delete();
  await advance(db, () => now);
  assert.equal(await read('throne_data/current'), undefined);
  await db.doc('throne_config/runtime').set({enabled: true, financialSafetyVersion: 2});
  await db.doc('throne_data/current').set({kingUid: 'legacy', currentBid: 3000});
  await advance(db, () => now + DAY);
  assert.deepEqual(await read('throne_data/current'), {kingUid: 'legacy', currentBid: 3000});
  await rejectsCode(offer('alice', 4000), 'failed-precondition');
});

test('missing accounts and inconsistent escrow abort the whole transaction', async () => {
  await seed(); await offer('alice', 500);
  await db.doc('users/alice').update({throneReservedPoints: 400});
  await rejectsCode(offer('bob', 600), 'failed-precondition');
  assert.equal((await read('users/bob')).titiBalance, 20000);
  await rejectsCode(advance(db, () => now + DAY), 'failed-precondition');
  assert.equal((await read('throne_data/current')).status, 'auction');
});

function userToken(uid) {
  const base = value => Buffer.from(JSON.stringify(value)).toString('base64url');
  return `${base({alg: 'none', typ: 'JWT'})}.${base({sub: uid, user_id: uid,
    aud: projectId, iss: `https://securetoken.google.com/${projectId}`,
    iat: Math.floor(Date.now()/1000), exp: Math.floor(Date.now()/1000) + 3600,
    firebase: {sign_in_provider: 'custom', identities: {}}})}.`;
}
async function client(path, method = 'GET', fields, uid = 'alice', mask) {
  const suffix = mask ? `?updateMask.fieldPaths=${mask}` : '';
  return fetch(`${root}/${path}${suffix}`, {method, headers: {
    Authorization: `Bearer ${userToken(uid)}`, 'Content-Type': 'application/json'},
    body: fields ? JSON.stringify({fields}) : undefined});
}

test('rules block direct throne, entitlement, history, escrow and receipt tampering', async () => {
  await seed();
  for (const path of ['throne_data/current', 'throne_bids/forged', 'throne_entitlements/alice',
    'throne_reigns/forged', 'throne_ledger/forged', 'throne_requests/alice/bids/forged',
    'throne_auctions/auction-1/competitors/alice', 'throne_reigns/auction-1/reactions/alice', 'throne_config/runtime']) {
    const response = await client(path, 'PATCH', {uid: {stringValue: 'alice'}});
    assert.equal(response.status, 403, `${path}: ${await response.text()}`);
  }
  const response = await client('users/alice', 'PATCH', {throneReservedPoints: {integerValue: '999'}}, 'alice', 'throneReservedPoints');
  assert.equal(response.status, 403);
  assert.equal((await client('users/alice', 'PATCH', {fullName: {stringValue: 'new name'}}, 'alice', 'fullName')).status, 200);
});

test('read permissions preserve public state and isolate request receipts', async () => {
  await seed(); await offer('alice', 100);
  assert.equal((await client('throne_data/current')).status, 200);
  assert.equal((await client('throne_requests/alice/bids/alice-100', 'GET', null, 'alice')).status, 200);
  assert.equal((await client('throne_requests/alice/bids/alice-100', 'GET', null, 'bob')).status, 403);
  await offer('bob', 10000);
  assert.equal((await client('users/bob', 'DELETE', null, 'bob')).status, 200);
  // Completed crowns remain authoritative after account deletion/recreation.
  assert.equal((await read('throne_entitlements/bob')).coronationCount, 1);
});

test('callable rejects unauthenticated clients', async () => {
  await rejectsCode(throne.placeThroneBid.run({data: {amount: 100}}), 'unauthenticated');
});

test('a request crossing the deadline during transaction reads is rejected atomically', async () => {
  await seed();
  let ticks = 0;
  await rejectsCode(offer('alice', 100, 'cross-deadline', 'auction-1',
    () => ++ticks === 1 ? now + DAY - 1 : now + DAY), 'deadline-exceeded');
  assert.equal((await read('users/alice')).titiBalance, 20000);
  assert.equal((await db.collection('throne_ledger').get()).size, 0);
});

test('initial auction creation is serialized and absent activation creates no state', async () => {
  await seed();
  await db.doc('throne_data/current').delete();
  await Promise.all([advance(db, () => now), advance(db, () => now)]);
  const state = await read('throne_data/current');
  assert.equal(state.status, 'auction');
  const id = state.auctionId;
  await advance(db, () => now);
  assert.equal((await read('throne_data/current')).auctionId, id);
});

test('top competitors are unique users, scoped to one auction, with historical bids retained', async () => {
  await seed();
  await offer('alice', 100); await offer('bob', 200); await offer('carol', 300); await offer('alice', 400);
  const leaders = await db.collection('throne_auctions/auction-1/competitors').orderBy('amount', 'desc').limit(3).get();
  assert.deepEqual(leaders.docs.map(doc => doc.data().uid), ['alice', 'carol', 'bob']);
  assert.equal((await read('users/carol')).throneReservedPoints, 0);
  assert.equal((await read('users/alice')).throneReservedPoints, 400);
  assert.equal((await db.collection('throne_bids').get()).size, 4);
});

test('hall query pages completed reigns without loading active reigns', async () => {
  await seed();
  const batch = db.batch();
  for (let i = 0; i < 25; i++) batch.set(db.doc(`throne_reigns/history-${i}`), {
    completed: i !== 24, crownedAt: Timestamp.fromMillis(now + i)});
  await batch.commit();
  const query = db.collection('throne_reigns').where('completed', '==', true).orderBy('crownedAt', 'desc').limit(20);
  const first = await query.get();
  const second = await query.startAfter(first.docs.at(-1)).get();
  assert.equal(first.size, 20); assert.equal(second.size, 4);
  assert.equal(new Set([...first.docs, ...second.docs].map(doc => doc.id)).size, 24);
});

test('rules preserve account deletion after settlement but reject deleting live escrow', async () => {
  await seed(); await offer('alice', 100);
  assert.equal((await client('users/alice', 'DELETE', null, 'alice')).status, 403);
});

test('documented legacy balance-policy blocker cannot silently activate financial bidding', async () => {
  await seed();
  await db.doc('throne_config/runtime').delete();
  // Intentionally demonstrates an existing policy outside the isolated throne changes.
  const response = await client('users/alice', 'PATCH', {titiBalance: {integerValue: '999999'}}, 'alice', 'titiBalance');
  assert.equal(response.status, 200);
  await rejectsCode(offer('alice', 10000), 'failed-precondition');
  assert.equal((await db.collection('throne_ledger').get()).size, 0);
});

test('callable rejects a switched account before any money operation', async () => {
  await rejectsCode(throne.placeThroneBid.run({auth: {uid: 'alice'}, data: {uid: 'bob', amount: 100}}), 'unauthenticated');
});

test.after(async () => { await db.terminate(); });
