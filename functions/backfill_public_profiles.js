'use strict';
// Offline administrative preparation. Never exported as a deployed function.
const {initializeApp} = require('firebase-admin/app');
const {getFirestore, FieldPath} = require('firebase-admin/firestore');
const {readFileSync} = require('node:fs');
const {resolve} = require('node:path');
const {testing: {syncProfile, projectProfile}} = require('./public_profiles');

async function syncReverseBlock(db, sourceUid, targetUid) {
  if (typeof targetUid !== 'string' || !targetUid || targetUid.includes('/') || targetUid === sourceUid) return;
  await db.runTransaction(async tx => {
    const source = (await tx.get(db.doc(`users/${sourceUid}`))).data();
    const blocked = await tx.get(db.doc(`users/${sourceUid}/blocked/${targetUid}`));
    const target = await tx.get(db.doc(`users/${targetUid}`));
    const list = [...(Array.isArray(source?.blockedUsers) ? source.blockedUsers : []),
      ...(Array.isArray(source?.blocked) ? source.blocked : [])];
    if (!source || !target.exists || (!blocked.exists && !list.includes(targetUid))) return;
    const ref = db.doc(`users/${targetUid}/blockedBy/${sourceUid}`);
    const marker = await tx.get(ref);
    if (!marker.exists) tx.set(ref, {by: sourceUid});
  });
}
async function prepare(db, {apply = false} = {}) {
  let cursor, scanned = 0, mismatches = 0, missingReverseBlocks = 0;
  while (true) {
    let query = db.collection('users').orderBy(FieldPath.documentId()).limit(200);
    if (cursor) query = query.startAfter(cursor);
    const page = await query.get();
    if (page.empty) break;
    for (const doc of page.docs) {
      const publicDoc = await db.doc(`public_profiles/${doc.id}`).get();
      const expected = projectProfile(doc.id, doc.data());
      const {isDeepStrictEqual} = require('node:util');
      if (!publicDoc.exists || !isDeepStrictEqual(publicDoc.data(), expected)) mismatches++;
      if (apply) await syncProfile(db, doc.id);
      // Preserve legacy array-only blocks without publishing the arrays.
      const data = doc.data();
      const blocks = await db.collection(`users/${doc.id}/blocked`).get();
      const targets = new Set([
        ...(Array.isArray(data.blockedUsers) ? data.blockedUsers : []),
        ...(Array.isArray(data.blocked) ? data.blocked : []),
        ...blocks.docs.map(d => d.id),
      ]);
      for (const target of targets) {
        if (typeof target !== 'string' || !target || target.includes('/') || target === doc.id) continue;
        if (!(await db.doc(`users/${target}`).get()).exists) continue;
        if (!(await db.doc(`users/${target}/blockedBy/${doc.id}`).get()).exists) missingReverseBlocks++;
        if (apply) await syncReverseBlock(db, doc.id, target);
      }
      scanned++;
    }
    cursor = page.docs.at(-1);
  }
  // Remove orphan public documents left by historical/manual deletes.
  // Each deletion rechecks the source transactionally before deleting anything.
  let publicCursor, orphans = 0;
  while (true) {
    let query = db.collection('public_profiles').orderBy(FieldPath.documentId()).limit(200);
    if (publicCursor) query = query.startAfter(publicCursor);
    const page = await query.get();
    if (page.empty) break;
    for (const doc of page.docs) {
      if (!(await db.doc(`users/${doc.id}`).get()).exists) {
        orphans++;
        if (apply) await syncProfile(db, doc.id);
      }
    }
    publicCursor = page.docs.at(-1);
  }
  return {mode: apply ? 'apply' : 'read-only', scanned, mismatches, missingReverseBlocks, orphans};
}
async function main() {
  const args = process.argv.slice(2);
  if (args.some(a => a !== '--apply' && !a.startsWith('--project='))) throw Error('Use --project=ID [--apply]');
  const project = args.find(a => a.startsWith('--project='))?.slice(10);
  const expected = JSON.parse(readFileSync(resolve(__dirname, '../.firebaserc'), 'utf8')).projects.default;
  const emulator = process.env.FIRESTORE_EMULATOR_HOST;
  if (!project || (emulator
    ? !/^127\.0\.0\.1:\d+$/.test(emulator) || !project.startsWith('demo-')
    : project !== expected)) throw Error('An explicit matching Firebase project is required');
  initializeApp({projectId: project});
  const db = getFirestore();
  try { console.log(JSON.stringify(await prepare(db, {apply: args.includes('--apply')}))); }
  finally { await db.terminate(); }
}
if (require.main === module) main().catch(error => { console.error(error.message); process.exitCode = 1; });
module.exports = {prepare, syncReverseBlock};
