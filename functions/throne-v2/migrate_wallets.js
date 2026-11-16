'use strict';
// Offline administrative migration. Nothing in this file is a deployed function.
const {initializeApp} = require('firebase-admin/app');
const {getFirestore, Timestamp} = require('firebase-admin/firestore');
const {readFileSync, writeFileSync} = require('node:fs');
const {resolve} = require('node:path');
const {createHash, randomUUID} = require('node:crypto');
const {core: {whole, entry}} = require('./wallet');
function canonical(value) {
  if (value?.toMillis) return {timestamp: value.toMillis()};
  if (Array.isArray(value)) return value.map(canonical);
  if (value && typeof value === 'object') return Object.fromEntries(Object.keys(value).sort().map(k => [k, canonical(value[k])]));
  return value;
}
const digest = value => createHash('sha256').update(JSON.stringify(canonical(value))).digest('hex');
async function inspect(db) {
  const users = await db.collection('users').get();
  const legacy = await db.collection('throne_wallets').get();
  const state = (await db.doc('throne_data/current').get()).data() ?? null;
  const cfg = (await db.doc('wallet_config/runtime').get()).data();
  const wallets = new Map(legacy.docs.map(d => [d.id, d.data()]));
  const ids = new Set(users.docs.map(d => d.id));
  const orphans = [...wallets.keys()].filter(uid => !ids.has(uid));
  return {version: 2, runId: cfg?.migrationRunId ?? null, stateDigest: digest(state),
    orphans, accounts: users.docs.map(d => ({uid: d.id,
      expectedDigest: digest({user: d.data(), legacy: wallets.get(d.id) ?? null}),
      oldWalletBalance: d.data().tiniBalance ?? 0,
      oldThroneWallet: wallets.get(d.id) ?? null,
      // Explicitly choose the final available balance; do not add two sources blindly.
      available: null, classification: null, reason: null}))};
}
async function begin(db, runId) {
  if (!/^[\w-]{1,100}$/.test(runId)) throw Error('Invalid migration ID');
  return db.runTransaction(async tx => {
    const ref = db.doc('wallet_config/runtime'), cfg = (await tx.get(ref)).data();
    if (cfg?.version === 2 && !cfg.migrationInProgress) throw Error('Already migrated');
    if (cfg?.migrationRunId && cfg.migrationRunId !== runId) throw Error('Another migration is in progress');
    tx.set(ref, {enabled: false, purchasesEnabled: false, migrationInProgress: true, migrationRunId: runId}, {merge: true});
    tx.set(db.doc('throne_config/runtime'), {enabled: false}, {merge: true});
  });
}
async function apply(db, plan) {
  if (plan.version !== 2 || !plan.runId || !Array.isArray(plan.accounts)) throw Error('Invalid reviewed manifest');
  const initial = (await db.doc('wallet_config/runtime').get()).data();
  if (initial?.version === 2 && !initial.migrationInProgress) {
    if (initial.completedPlanDigest !== digest(plan)) throw Error('Migration already completed with a different manifest');
    return {alreadyApplied: true};
  }
  const report = await inspect(db);
  if (report.orphans.length || report.stateDigest !== plan.stateDigest)
    throw Error('Resolve orphan wallets or regenerate the state snapshot first');
  const unique = new Set(plan.accounts.map(a => a.uid));
  if (unique.size !== plan.accounts.length || report.accounts.some(a => !unique.has(a.uid))) throw Error('Manifest must include every account once');
  for (const a of plan.accounts) {
    whole(a.available);
    if (!['test', 'reviewed_opening'].includes(a.classification) || typeof a.reason !== 'string' || a.reason.length < 8)
      throw Error('Every opening balance needs explicit provenance, including test/discard choices');
  }
  for (const a of plan.accounts) {
    await db.runTransaction(async tx => {
      const cfg = (await tx.get(db.doc('wallet_config/runtime'))).data();
      if (!cfg?.migrationInProgress || cfg.migrationRunId !== plan.runId) throw Error('Begin migration first');
      const userRef = db.doc(`users/${a.uid}`), legacyRef = db.doc(`throne_wallets/${a.uid}`);
      const marker = db.doc(`wallet_migrations/${plan.runId}/accounts/${a.uid}`);
      const prior = (await tx.get(marker)).data();
      const reviewed = digest(a);
      if (prior) { if (prior.reviewed !== reviewed) throw Error('Changed manifest on retry'); return; }
      const user = (await tx.get(userRef)).data();
      const old = (await tx.get(legacyRef)).data() ?? null;
      const state = (await tx.get(db.doc('throne_data/current'))).data();
      if (!user || digest({user, legacy: old}) !== a.expectedDigest) throw Error(`Snapshot changed for ${a.uid}`);
      const reserved = state?.status === 'auction' && state.leaderUid === a.uid ? whole(state.currentBid) : 0;
      if ((old?.reservedPoints ?? 0) !== reserved) throw Error('Legacy escrow does not match current auction');
      tx.update(userRef, {walletVersion: 2, tiniBalance: a.available, throneReservedPoints: reserved,
        walletDebt: 0, purchaseAccountToken: randomUUID()});
      if (old) tx.update(legacyRef, {availablePoints: 0, reservedPoints: 0, migratedToWalletVersion: 2, migrationRunId: plan.runId});
      tx.create(marker, {reviewed, userBefore: user, legacyBefore: old, available: a.available,
        reserved, classification: a.classification, reason: a.reason, migratedAt: Timestamp.now()});
      entry(tx, db, a.uid, `migration_${plan.runId}`, 'migration', a.available,
        {classification: a.classification, reason: a.reason});
    });
  }
  // Cutover only after all account transactions commit. Existing reign/timestamps are preserved.
  await db.runTransaction(async tx => {
    const cfgRef = db.doc('wallet_config/runtime'), cfg = (await tx.get(cfgRef)).data();
    if (!cfg?.migrationInProgress || cfg.migrationRunId !== plan.runId) throw Error('Migration lock missing');
    const users = await tx.get(db.collection('users'));
    if (users.docs.some(d => d.data().walletVersion !== 2)) throw Error('New account appeared; regenerate/review manifest before cutover');
    const ref = db.doc('throne_data/current'), state = (await tx.get(ref)).data();
    if (digest(state ?? null) !== plan.stateDigest) throw Error('Throne state changed');
    if (state && state.schemaVersion !== 3) throw Error('Unsupported throne state; no reset performed');
    if (state) tx.update(ref, {walletVersion: 2});
    tx.set(cfgRef, {version: 2, enabled: true, migrationInProgress: false, purchasesEnabled: false, completedPlanDigest: digest(plan)}, {merge: true});
    // Bids remain paused until the operator activates them with the compatible app deployed.
  });
}
async function main() {
  const [command, ...args] = process.argv.slice(2);
  const flags = Object.fromEntries(args.map(v => {const m = /^--([\w-]+)=(.+)$/.exec(v); if (!m) throw Error('Use --key=value'); return [m[1], m[2]];}));
  const expected = JSON.parse(readFileSync(resolve(__dirname, '../../.firebaserc'))).projects.default;
  const project = flags.project, emulator = process.env.FIRESTORE_EMULATOR_HOST;
  if (!project || (emulator ? !/^127\.0\.0\.1:\d+$/.test(emulator) || !project.startsWith('demo-') : project !== expected)) throw Error('Explicit matching project required');
  initializeApp({projectId: project}); const db = getFirestore();
  if (command === 'inspect') {
    if (!flags.out) throw Error('--out required; reports contain private account data');
    writeFileSync(flags.out, JSON.stringify(await inspect(db), null, 2), {mode: 0o600});
    console.log('Read-only report written; available/classification/reason require review.');
  } else if (command === 'begin') await begin(db, flags['run-id']);
  else if (command === 'apply') await apply(db, JSON.parse(readFileSync(flags.manifest)));
  else throw Error('Commands: inspect, begin, apply');
  await db.terminate();
}
if (require.main === module) main().catch(e => {console.error(e.message); process.exitCode = 1;});
module.exports = {inspect, begin, apply, digest};