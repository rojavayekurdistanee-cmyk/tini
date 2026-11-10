'use strict';
// Administrative tools only. This file is never exported as a callable function.
const {randomUUID} = require('node:crypto');
const {initializeApp} = require('firebase-admin/app');
const {getFirestore, Timestamp} = require('firebase-admin/firestore');
const {getAuth} = require('firebase-admin/auth');
const {readFileSync} = require('node:fs');
const {resolve} = require('node:path');
const {testing: {auction}} = require('./throne');

function whole(value, max) {
  if (!Number.isSafeInteger(value) || value < 1 || value > max) throw new Error('Invalid positive point amount');
  return value;
}
async function grantPoints(db, uid, amount, operationId) {
  whole(amount, 100000);
  if (typeof uid !== 'string' || !uid || uid.includes('/')) throw new Error('Invalid account UID');
  if (!/^[A-Za-z0-9_-]{1,100}$/.test(operationId || '')) throw new Error('A stable operation ID is required');
  return db.runTransaction(async tx => {
    const receiptRef = db.doc(`throne_ledger/grant_${uid}_${operationId}`);
    const previous = await tx.get(receiptRef);
    if (previous.exists) {
      if (previous.data().uid !== uid || previous.data().amount !== amount) throw new Error('Operation ID already used with a different amount');
      return {applied: false, operationId};
    }
    const config = (await tx.get(db.doc('wallet_config/runtime'))).data();
    if (config?.version !== 2 || config?.migrationInProgress || config?.purchasesEnabled)
      throw new Error('Test grants require a migrated wallet with real purchases disabled');
    const ref = db.doc(`users/${uid}`);
    const user = await tx.get(ref);
    const wallet = require('./wallet').core.wallet(user.data());
    const balance = require('./wallet').core.whole(wallet.tiniBalance + amount);
    tx.update(ref, {tiniBalance: balance});
    require('./wallet').core.entry(tx, db, uid, `grant_${operationId}`, 'test_grant', amount);
    tx.create(receiptRef, {uid, amount, type: 'admin_grant', operationId, timestamp: Timestamp.now()});
    return {applied: true, operationId};
  });
}
async function activate(db, clock = Date.now) {
  const id = randomUUID();
  return db.runTransaction(async tx => {
    const ref = db.doc('throne_data/current');
    const state = (await tx.get(ref)).data();
    const walletConfig = (await tx.get(db.doc('wallet_config/runtime'))).data();
    if (walletConfig?.version !== 2 || walletConfig?.migrationInProgress) throw new Error('Complete wallet migration first');
    if (state && state.schemaVersion !== 3) {
      // Only a provably empty v2 auction can be upgraded without moving or refunding money.
      if (!(state.schemaVersion === 2 && state.status === 'auction' && state.currentBid === 0 &&
        !state.leaderUid && !state.kingUid && state.isLocked === false))
        throw new Error('Existing legacy throne state requires review; it was not reset');
    }
    if (!state || state.schemaVersion !== 3) tx.set(ref, auction(id, clock(), true));
    tx.set(db.doc('throne_config/runtime'), {enabled: true, financialSafetyVersion: 3}, {merge: true});
    return {enabled: true, schemaVersion: 3};
  });
}
async function main() {
  const [command, ...args] = process.argv.slice(2);
  const flags = Object.fromEntries(args.map(arg => {
    const match = /^--([a-z-]+)=(.+)$/.exec(arg);
    if (!match) throw new Error('Use --name=value flags');
    return [match[1], match[2]];
  }));
  const project = flags.project;
  if (!project) throw new Error('Explicit --project is required');
  const emulator = process.env.FIRESTORE_EMULATOR_HOST;
  if (emulator && (!/^127\.0\.0\.1:\d+$/.test(emulator) || !project.startsWith('demo-')))
    throw new Error('Emulator tools require loopback and a demo-* project');
  const expected = JSON.parse(readFileSync(resolve(__dirname, '../../.firebaserc'), 'utf8')).projects.default;
  if (!emulator && project !== expected) throw new Error('Project differs from the checked-in Firebase configuration');
  initializeApp({projectId: project});
  const db = getFirestore();
  if (command === 'status') {
    const state = (await db.doc('throne_data/current').get()).data();
    const config = (await db.doc('throne_config/runtime').get()).data();
    const walletConfig = (await db.doc('wallet_config/runtime').get()).data();
    console.log(JSON.stringify({project, schemaVersion: state?.schemaVersion ?? null,
      state: state?.status ?? null, enabled: config?.enabled === true,
      financialSafetyVersion: config?.financialSafetyVersion ?? null, walletVersion: walletConfig?.version ?? null, purchasesEnabled: walletConfig?.purchasesEnabled === true, migrationInProgress: walletConfig?.migrationInProgress === true}));
  } else if (command === 'activate') {
    console.log(JSON.stringify(await activate(db)));
  } else if (command === 'pause') {
    await db.doc('throne_config/runtime').set({enabled: false}, {merge: true});
    console.log(JSON.stringify({enabled: false}));
  } else if (command === 'grant') {
    // Authentication account existence is verified outside the transaction, before granting test points.
    await getAuth().getUser(flags.uid);
    console.log(JSON.stringify(await grantPoints(db, flags.uid, Number(flags.points), flags['operation-id'])));
  } else {
    throw new Error('Commands: status, activate, pause, grant');
  }
  await db.terminate();
}
if (require.main === module) main().catch(error => { console.error(error.message); process.exitCode = 1; });
module.exports = {grantPoints, activate};