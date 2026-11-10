'use strict';
const {test, before, beforeEach, after} = require('node:test');
const assert = require('node:assert/strict');
const {initializeApp, deleteApp} = require('firebase-admin/app');
const {getFirestore, Timestamp} = require('firebase-admin/firestore');
const {testing: {bid, auction, advance, DAY}} = require('../throne');
const {testing: {deliver, revoke}} = require('../purchases');
const {testing: {reserve, finish}} = require('../box_wallet');
const {testing: {create}} = require('../wallet');
const {grantPoints} = require('../admin');
const {inspect, begin, apply} = require('../migrate_wallets');
const {verify} = require('../purchase_verifier');
if (process.env.FIRESTORE_EMULATOR_HOST !== '127.0.0.1:8080' || process.env.GCLOUD_PROJECT !== 'demo-tini-throne')
  throw Error('Tests require loopback Firestore emulator and demo-tini-throne');
let app, db;
const now = 1800000000000;
const user = (balance = 1000) => ({walletVersion: 2, tiniBalance: balance, throneReservedPoints: 0,
  boxReservedPoints: 0, walletDebt: 0, purchaseAccountToken: 'account', fullName: 'Test'});
const get = async path => (await db.doc(path).get()).data();
const purchase = (id = 'a', productId = 'coins_100') => ({id: id.repeat(64), productId, platform: 'android', sandbox: true});
async function base() {
  await db.doc('wallet_config/runtime').set({version: 2, enabled: true, purchasesEnabled: true, allowSandbox: true});
  await db.doc('throne_config/runtime').set({enabled: true, financialSafetyVersion: 3});
  await db.doc('throne_data/current').set(auction('auction', now, true));
  for (const uid of ['a','b','seller']) await db.doc(`users/${uid}`).set(user());
  await db.doc('posts/box').set({uid: 'seller', isMysteryBox: true, boxPrice: 800, boxRarity: 'gold', boxSold: false});
}
before(() => {app = initializeApp({projectId: 'demo-tini-throne'}); db = getFirestore(app);});
beforeEach(async () => {
  const response = await fetch('http://127.0.0.1:8080/emulator/v1/projects/demo-tini-throne/databases/(default)/documents', {method: 'DELETE'});
  assert.equal(response.ok, true); await base();
});
after(async () => {await db.terminate(); await deleteApp(app);});
test('one global receipt delivers once under concurrent retries; another user cannot claim it', async () => {
  await Promise.all([deliver(db,'a',purchase()),deliver(db,'a',purchase())]);
  assert.equal((await get('users/a')).tiniBalance,1100);
  await assert.rejects(deliver(db,'b',purchase()));
  assert.equal((await db.collection('users/a/transactions').get()).size,1);
});
test('disabled purchases and sandbox in production cannot deliver', async () => {
  await db.doc('wallet_config/runtime').update({allowSandbox:false});
  await assert.rejects(deliver(db,'a',purchase()));
  assert.equal((await get('users/a')).tiniBalance,1000);
});
test('refund before purchase produces a tombstone; no later credit', async () => {
  await revoke(db, purchase().id);
  await assert.rejects(deliver(db,'a',purchase()));
  assert.equal((await get('users/a')).tiniBalance,1000);
});
test('refund after spending records debt once and future purchased coins pay debt first', async () => {
  await deliver(db,'a',purchase('a','coins_500'));
  await db.doc('users/a').update({tiniBalance:20});
  await Promise.all([revoke(db,purchase().id),revoke(db,purchase().id)]);
  assert.equal((await get('users/a')).walletDebt,530);
  await assert.rejects(bid(db,'a',{requestId:'bid',auctionId:'auction',amount:1},()=>now));
  await deliver(db,'a',purchase('b'));
  assert.equal((await get('users/a')).walletDebt,430);
  assert.equal((await get('users/a')).tiniBalance,0);
});
test('bid reserve, self raise delta, outbid refund, and receipt replay use one wallet', async () => {
  await bid(db,'a',{requestId:'first',auctionId:'auction',amount:100},()=>now);
  await bid(db,'a',{requestId:'raise',auctionId:'auction',amount:200},()=>now);
  assert.equal((await get('users/a')).tiniBalance,800);
  await bid(db,'b',{requestId:'other',auctionId:'auction',amount:300},()=>now);
  assert.equal((await get('users/a')).tiniBalance,1000);
  assert.equal((await get('users/a')).throneReservedPoints,0);
  await bid(db,'b',{requestId:'other',auctionId:'auction',amount:300},()=>now);
  assert.equal((await get('users/b')).tiniBalance,700);
});
test('instant crown settles reservation without a second debit and retains seven days', async () => {
  await db.doc('users/a').update({tiniBalance:20000});
  await bid(db,'a',{requestId:'instant',auctionId:'auction',amount:10000},()=>now);
  const a = await get('users/a'), state = await get('throne_data/current');
  assert.equal(a.tiniBalance,10000); assert.equal(a.throneReservedPoints,0);
  assert.equal(state.lockEndTime.toMillis()-now,7*DAY);
});
test('scheduled crown settles held points once and next auction retains wallet version', async () => {
  await bid(db,'a',{requestId:'first',auctionId:'auction',amount:100},()=>now);
  await advance(db,()=>now+DAY); await advance(db,()=>now+DAY);
  assert.equal((await get('users/a')).tiniBalance,900);
  assert.equal((await get('users/a')).throneReservedPoints,0);
  await advance(db,()=>now+2*DAY);
  assert.equal((await get('throne_data/current')).walletVersion,2);
});
test('simultaneous box reservation and throne bid cannot spend the same money', async () => {
  const results = await Promise.allSettled([
    bid(db,'a',{requestId:'bid',auctionId:'auction',amount:800},()=>now),
    reserve(db,'a',{postId:'box',requestId:'box1'},false,()=>now),
  ]);
  assert.equal(results.filter(r=>r.status==='fulfilled').length,1);
  const a = await get('users/a');
  assert.equal(a.tiniBalance,200); assert.equal(a.throneReservedPoints+a.boxReservedPoints,800);
});
test('box purchase pays seller once; repeated confirmation does not extend badge', async () => {
  const held = await reserve(db,'a',{postId:'box',requestId:'hold'},false,()=>now);
  await finish(db,'a',{postId:'box',token:held.token},'buy',()=>now);
  const end = (await get('users/a')).badgeEndsAt.toMillis();
  await finish(db,'a',{postId:'box',token:held.token},'buy',()=>now+10000);
  assert.equal((await get('users/seller')).tiniBalance,1800);
  assert.equal((await get('users/a')).tiniBalance,200);
  assert.equal((await get('users/a')).boxReservedPoints,0);
  assert.equal((await get('users/a')).badgeEndsAt.toMillis(),end);
});
test('expired box reservation refunds once and cannot be bought afterwards', async () => {
  const held = await reserve(db,'a',{postId:'box',requestId:'hold'},false,()=>now);
  await finish(db,null,{postId:'box'},'expire',()=>now+600001);
  await finish(db,'a',{postId:'box',token:held.token},'cancel',()=>now+600002);
  assert.equal((await get('users/a')).tiniBalance,1000);
  assert.equal((await get('users/seller')).tiniBalance,1000);
});
test('forged admin profile does not permit a free box; wrong token rejected', async () => {
  await db.doc('users/a').update({isAdmin:true,tiniBalance:0});
  await assert.rejects(reserve(db,'a',{postId:'box',requestId:'hold'},false,()=>now));
  await db.doc('users/a').update({tiniBalance:1000});
  await reserve(db,'a',{postId:'box',requestId:'hold'},false,()=>now);
  await assert.rejects(finish(db,'b',{postId:'box',token:'wrong'},'buy',()=>now));
});
test('wallet initialization never copies legacy balances or resets an existing wallet', async () => {
  assert.equal((await create(db,'a')).balance,1000);
  await db.doc('users/new').set({tiniBalance:0});
  await create(db,'new'); assert.equal((await get('users/new')).walletVersion,2);
  await db.doc('users/old').set({tiniBalance:900});
  await assert.rejects(create(db,'old')); assert.equal((await get('users/old')).tiniBalance,900);
});
test('test grants blocked when live purchases enabled', async () => {
  await assert.rejects(grantPoints(db,'a',100,'test'));
  assert.equal((await get('users/a')).tiniBalance,1000);
});
test('malformed and unknown store proof rejected before network', async () => {
  await assert.rejects(verify({productId:'invented',proof:'fake'},'account',{}));
  await assert.rejects(verify({productId:'coins_100',platform:'unknown',proof:'long-enough-fake'},'account',{}));
});
test('reviewed migration preserves an active reign and never debits the king again', async () => {
  await db.doc('wallet_config/runtime').delete();
  await db.doc('users/a').set({tiniBalance:50});
  await db.doc('throne_wallets/a').set({schemaVersion:1,availablePoints:90000,reservedPoints:0});
  const state = {...auction('old',now),status:'reign',kingUid:'a',lockEndTime:Timestamp.fromMillis(now+7*DAY),coronationId:'old'};
  await db.doc('throne_data/current').set(state);
  await begin(db,'reviewed');
  const plan = await inspect(db);
  for (const a of plan.accounts) Object.assign(a,{available:a.uid==='a'?90000:1000,classification:'test',reason:'Developer test balance explicitly retained'});
  await apply(db,plan);
  await apply(db,plan); // Retried full migration is a no-op.
  const current = await get('throne_data/current');
  assert.equal(current.kingUid,'a'); assert.equal(current.lockEndTime.toMillis(),state.lockEndTime.toMillis());
  assert.equal((await get('users/a')).tiniBalance,90000);
  assert.equal((await get('wallet_config/runtime')).purchasesEnabled,false);
});

test('Google verification checks purchase state, quantity, account binding, and sandbox status', async () => {
  const {testing: {google}} = require('../purchase_verifier');
  const valid = {purchaseState:0,quantity:1,obfuscatedExternalAccountId:'account',purchaseType:0};
  const client = data => ({request: async () => ({data})});
  const verified = await google('coins_100','store-token','account',{allowSandbox:true},client(valid));
  assert.equal(verified.id.length,64);
  for (const changes of [{purchaseState:1},{purchaseState:2},{quantity:2},{obfuscatedExternalAccountId:'other'}]) {
    await assert.rejects(google('coins_100','store-token','account',{allowSandbox:true},client({...valid,...changes})));
  }
  await assert.rejects(google('coins_100','store-token','account',{allowSandbox:false},client(valid)));
});

test('signed-store refund reversal restores coins/debt once and permits a subsequent refund', async () => {
  const {testing: {reverseRefund}} = require('../purchases');
  await deliver(db,'a',purchase());
  await revoke(db,purchase().id);
  await reverseRefund(db,purchase().id); await reverseRefund(db,purchase().id);
  assert.equal((await get('users/a')).tiniBalance,1100);
  await revoke(db,purchase().id);
  assert.equal((await get('users/a')).tiniBalance,1000);
});

test('out-of-order store notifications do not reapply a superseded refund', async () => {
  const {testing: {reverseRefund}} = require('../purchases');
  await revoke(db,purchase().id,100);
  await reverseRefund(db,purchase().id,200);
  await revoke(db,purchase().id,100);
  await deliver(db,'a',purchase());
  assert.equal((await get('users/a')).tiniBalance,1100);
  await revoke(db,purchase().id,300);
  await reverseRefund(db,purchase().id,200);
  assert.equal((await get('users/a')).tiniBalance,1000);
});

test('outbid refund pays chargeback debt from the released escrow before restoring available money', async () => {
  await db.doc('users/a').update({tiniBalance:0});
  await deliver(db,'a',purchase());
  await bid(db,'a',{requestId:'held',auctionId:'auction',amount:100},()=>now);
  await revoke(db,purchase().id);
  assert.equal((await get('users/a')).walletDebt,100);
  await bid(db,'b',{requestId:'outbid',auctionId:'auction',amount:101},()=>now);
  assert.equal((await get('users/a')).walletDebt,0);
  assert.equal((await get('users/a')).tiniBalance,0);
});

test('migration moves active auction escrow separately and settles it without another debit', async () => {
  await db.doc('wallet_config/runtime').delete();
  await db.doc('users/a').set({tiniBalance:50});
  await db.doc('throne_wallets/a').set({schemaVersion:1,availablePoints:900,reservedPoints:100});
  await db.doc('throne_data/current').set({...auction('oldauction',now),leaderUid:'a',leaderName:'Test',leaderAvatar:'',currentBid:100});
  await begin(db,'escrow');
  const plan = await inspect(db);
  for (const a of plan.accounts) Object.assign(a,{available:a.uid==='a'?900:1000,classification:'test',reason:'Reviewed opening balances; exclude held points'});
  await apply(db,plan);
  assert.equal((await get('users/a')).throneReservedPoints,100);
  assert.equal((await get('throne_wallets/a')).reservedPoints,0);
  await advance(db,()=>now+DAY);
  assert.equal((await get('users/a')).tiniBalance,900);
  assert.equal((await get('users/a')).throneReservedPoints,0);
});
test('an externally deleted box still refunds the authoritative hold on expiry', async () => {
  await reserve(db,'a',{postId:'box',requestId:'hold'},false,()=>now);
  await db.doc('posts/box').delete();
  await finish(db,null,{postId:'box'},'expire',()=>now+600001);
  assert.equal((await get('users/a')).tiniBalance,1000);
  assert.equal((await get('box_holds/box')).expiresAt,null);
});
