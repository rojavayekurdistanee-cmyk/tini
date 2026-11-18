'use strict';
const {getFirestore, FieldValue} = require('firebase-admin/firestore');
const {getAuth} = require('firebase-admin/auth');
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {onDocumentCreated} = require('firebase-functions/v2/firestore');

const fail = (message) => { throw new HttpsError('failed-precondition', message); };
function zero(data, fields) {
  for (const key of fields) {
    const value = data && Object.hasOwn(data, key) ? data[key] : 0;
    if (!Number.isSafeInteger(value) || value !== 0)
      fail('لا يمكن إغلاق الحساب مع وجود رصيد أو نقاط محجوزة أو التزامات مالية.');
  }
}
async function requestDeletion(db, auth, request, now = Date.now()) {
  const uid = request.auth?.uid;
  if (!uid || request.data?.uid !== uid)
    throw new HttpsError('unauthenticated', 'أعد تسجيل الدخول إلى الحساب المطلوب إغلاقه.');
  const seconds = request.auth.token?.auth_time;
  if (!Number.isFinite(seconds) || seconds * 1000 > now + 60000 || now - seconds * 1000 > 300000)
    throw new HttpsError('failed-precondition', 'للأمان، سجّل الخروج ثم سجّل الدخول مجدداً قبل إغلاق الحساب.', {reason: 'recent-login-required'});
  const jobRef = db.doc(`account_deletions/${uid}`);
  // Existing requests remain idempotent even after the Auth user is removed.
  if ((await jobRef.get()).exists) return {accepted: true};
  const account = await auth.getUser(uid);
  if (account.disabled) throw new HttpsError('permission-denied', 'الحساب غير متاح.');
  await db.runTransaction(async tx => {
    const [job, user, legacy, config, throne] = await tx.getAll(jobRef,
      db.doc(`users/${uid}`), db.doc(`throne_wallets/${uid}`),
      db.doc('wallet_config/runtime'), db.doc('throne_data/current'));
    if (job.exists) return;
    if (config.data()?.migrationInProgress === true) fail('حاول لاحقاً؛ تجري صيانة المحفظة.');
    zero(user.data(), ['tiniBalance', 'throneReservedPoints', 'walletDebt']);
    zero(legacy.data(), ['availablePoints', 'reservedPoints']);
    const state = throne.data();
    if ((state?.status === 'auction' && state.leaderUid === uid) ||
        (state?.status === 'reign' && state.kingUid === uid))
      fail('انتظر انتهاء المزايدة أو فترة العرش قبل إغلاق الحساب.');
    // Same transaction as the last wallet checks: concurrent credits/bids
    // either cause a retry or observe a missing user and cannot spend it.
    tx.create(jobRef, {status: 'pending', requestedAt: FieldValue.serverTimestamp()});
    tx.delete(db.doc(`users/${uid}`));
  });
  return {accepted: true};
}

// Only UID-owned prefixes are deleted. Never trust an editable profileImg URL
// as permission to delete an arbitrary R2 object belonging to someone else.
async function deleteProfileImages(uid) {
  const {S3Client, ListObjectsV2Command, DeleteObjectCommand} = require('@aws-sdk/client-s3');
  const {R2_ACCOUNT_ID, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, R2_BUCKET_NAME} = process.env;
  if (![R2_ACCOUNT_ID, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, R2_BUCKET_NAME].every(Boolean))
    throw new Error('R2 configuration required for account cleanup');
  const client = new S3Client({region: 'auto', endpoint: `https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com`,
    credentials: {accessKeyId: R2_ACCESS_KEY_ID, secretAccessKey: R2_SECRET_ACCESS_KEY}});
  try {
    let token;
    do {
      const page = await client.send(new ListObjectsV2Command({Bucket: R2_BUCKET_NAME,
        Prefix: `profile_images/${uid}/`, ContinuationToken: token}));
      for (const object of page.Contents || []) await client.send(new DeleteObjectCommand({
        Bucket: R2_BUCKET_NAME, Key: object.Key}));
      token = page.IsTruncated ? page.NextContinuationToken : undefined;
    } while (token);
    for (const key of [`profile_images/${uid}`, `profile_images/${uid}.jpg`])
      await client.send(new DeleteObjectCommand({Bucket: R2_BUCKET_NAME, Key: key}));
  } finally { client.destroy(); }
}
async function processDeletion(db, auth, uid, removeImages = deleteProfileImages) {
  const ref = db.doc(`account_deletions/${uid}`);
  const job = await ref.get();
  if (!job.exists || job.data().status === 'completed') return;
  try {
    // Every operation is repeatable. A failed attempt is retried by Eventarc;
    // no scheduled polling, client connection or in-memory lease is required.
    try { await auth.deleteUser(uid); }
    catch (error) { if (error.code !== 'auth/user-not-found') throw error; }
    await db.doc(`public_profiles/${uid}`).delete();
    await require('./galaxy_matching_core').createMatching(db).sync(uid);
    await db.recursiveDelete(db.doc(`galaxy_match_inbox/${uid}`));
    await db.recursiveDelete(db.doc(`users/${uid}`));
    await db.doc(`archived_users/${uid}`).delete();
    // Manual export records have an explicit owner; do not touch other users.
    while (true) {
      const page = await db.collection('archived_users').where('uid', '==', uid).limit(100).get();
      if (page.empty) break;
      const batch = db.batch(); for (const doc of page.docs) batch.delete(doc.ref);
      await batch.commit();
    }
    await removeImages(uid);
    // Retain the minimal UID tombstone, not the email or birth date. It blocks
    // stale-token recreation of this UID, while a new UID can use the same email.
    await ref.set({status: 'completed', completedAt: FieldValue.serverTimestamp()});
  } catch (error) {
    await db.runTransaction(async tx => {
      const current = await tx.get(ref);
      if (current.data()?.status !== 'completed') tx.update(ref, {
        status: 'retrying', lastAttemptAt: FieldValue.serverTimestamp()});
    });
    throw error;
  }
}
exports.requestAccountDeletion = onCall({region: 'europe-west1'}, request =>
  requestDeletion(getFirestore(), getAuth(), request));
exports.processAccountDeletion = onDocumentCreated({region: 'europe-west1',
  document: 'account_deletions/{uid}', retry: true, timeoutSeconds: 540}, event =>
  processDeletion(getFirestore(), getAuth(), event.params.uid));
Object.defineProperty(exports, 'testing', {value: {requestDeletion, processDeletion, zero}});
