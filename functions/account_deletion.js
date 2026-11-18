'use strict';
const {getFirestore, FieldValue, Timestamp} = require('firebase-admin/firestore');
const {getAuth} = require('firebase-admin/auth');
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {randomUUID} = require('node:crypto');
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
    tx.create(jobRef, {status: 'pending', accountEmail: account.email || null,
      requestedAt: FieldValue.serverTimestamp()});
    tx.delete(db.doc(`users/${uid}`));
  });
  return {accepted: true};
}

// Canonical object keys only; never send arbitrary external URLs to R2.
function createStorage() {
  const {S3Client, ListObjectsV2Command, DeleteObjectCommand} = require('@aws-sdk/client-s3');
  const {R2_ACCOUNT_ID, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, R2_BUCKET_NAME} = process.env;
  if (![R2_ACCOUNT_ID, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, R2_BUCKET_NAME].every(Boolean))
    throw new Error('R2 configuration required for account cleanup');
  const client = new S3Client({region: 'auto', endpoint: `https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com`,
    credentials: {accessKeyId: R2_ACCESS_KEY_ID, secretAccessKey: R2_SECRET_ACCESS_KEY}});
  const hosts = new Set(['pub-e602981c5b0b476c92bdec7ba140e7de.r2.dev']);
  if (process.env.R2_PUBLIC_URL) hosts.add(new URL(process.env.R2_PUBLIC_URL).host);
  const key = value => {
    try {
      const url = new URL(value);
      if (url.protocol !== 'https:' || !hosts.has(url.host)) return null;
      const result = decodeURIComponent(url.pathname.slice(1));
      if (result.split('/').some(part => part === '..' || part === '.')) return null;
      return result;
    } catch (_) { return null; }
  };
  const remove = key => client.send(new DeleteObjectCommand({Bucket: R2_BUCKET_NAME, Key: key}));
  async function removeOwned(uid) {
    for (const prefix of [`profile_images/${uid}/`, `stories/${uid}/`, `thumbnails/${uid}/`, `videos/${uid}/`, `raw_videos/${uid}_`, `chat_media/${uid}/`, `private_media/${uid}/`, `group_media/${uid}/`]) {
      let token;
      do {
        const page = await client.send(new ListObjectsV2Command({Bucket: R2_BUCKET_NAME, Prefix: prefix, ContinuationToken: token}));
        for (const object of page.Contents || []) {
          // raw_videos has no UID directory. Validate the entire suffix so a
          // short/custom UID cannot also match another user's upload prefix.
          if (/^(chat_media|private_media|group_media)\//.test(prefix) && object.Key.split('/').length < 4) continue;
          if (prefix.startsWith('raw_videos/') && !/^\d+_[A-Z0-9]{8}\.mp4$/.test(object.Key.slice(prefix.length))) continue;
          await remove(object.Key);
        }
        token = page.IsTruncated ? page.NextContinuationToken : undefined;
      } while (token);
    }
    for (const name of [`profile_images/${uid}`, `profile_images/${uid}.jpg`, `profile_images/${uid}.webp`]) await remove(name);
  }
  async function removeGroup(groupId) {
    const prefix = `group_images/${groupId}_`;
    let token;
    do {
      const page = await client.send(new ListObjectsV2Command({Bucket: R2_BUCKET_NAME, Prefix: prefix, ContinuationToken: token}));
      for (const object of page.Contents || [])
        if (/^\d+\.(webp|jpg|png)$/.test(object.Key.slice(prefix.length))) await remove(object.Key);
      token = page.IsTruncated ? page.NextContinuationToken : undefined;
    } while (token);
  }
  return {key, remove, removeOwned, removeGroup, close: () => client.destroy()};
}
async function processDeletion(db, auth, uid, suppliedStorage) {
  const ref = db.doc(`account_deletions/${uid}`), owner = randomUUID();
  const claimed = await db.runTransaction(async tx => {
    const job = await tx.get(ref), data = job.data();
    if (!job.exists || data.status === 'completed') return false;
    if (data.leaseUntil?.toMillis() > Date.now()) throw new Error('Deletion is already processing; retry later');
    tx.update(ref, {status: 'processing', leaseOwner: owner,
      leaseUntil: Timestamp.fromMillis(Date.now() + 11 * 60 * 1000)});
    return true;
  });
  if (!claimed) return;
  let storage;
  try {
    try { await auth.deleteUser(uid); }
    catch (error) { if (error.code !== 'auth/user-not-found') throw error; }
    storage = suppliedStorage || createStorage();
    await require('./account_erasure').createErasure(db, uid, ref, storage).run();
    const completedAt = Timestamp.now();
    await ref.set({status: 'completed', completedAt,
      expiresAt: Timestamp.fromMillis(completedAt.toMillis() + 2 * 60 * 60 * 1000)});
  } catch (error) {
    await db.runTransaction(async tx => {
      const current = await tx.get(ref);
      if (current.data()?.leaseOwner === owner) tx.update(ref, {
        status: 'retrying', leaseOwner: FieldValue.delete(), leaseUntil: FieldValue.delete(),
        lastAttemptAt: FieldValue.serverTimestamp()});
    });
    throw error;
  } finally { storage?.close?.(); }
}
exports.requestAccountDeletion = onCall({region: 'europe-west1'}, request =>
  requestDeletion(getFirestore(), getAuth(), request));
exports.processAccountDeletion = onDocumentCreated({region: 'europe-west1',
  document: 'account_deletions/{uid}', retry: true, timeoutSeconds: 540}, event =>
  processDeletion(getFirestore(), getAuth(), event.params.uid));
Object.defineProperty(exports, 'testing', {value: {requestDeletion, processDeletion, zero, createStorage}});