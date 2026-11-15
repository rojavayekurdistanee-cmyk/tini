'use strict';
const {getFirestore} = require('firebase-admin/firestore');
const {onDocumentWritten} = require('firebase-functions/v2/firestore');
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {isDeepStrictEqual} = require('node:util');

// Explicit allowlist: new account fields are PRIVATE unless deliberately added.
// Do not add contacts, birth dates, balances, purchase tokens, security settings,
// block lists, search history or notification tokens to this list.
const PUBLIC_FIELDS = Object.freeze([
  'fullName', 'fullName_lowercase', 'username', 'username_lowercase',
  'profileImg', 'bio', 'createdAt', 'profileCompleted',
  'followers', 'following', 'likes', 'crownNumber',
  'badge', 'badgeEndsAt', 'throneCoronations', 'throneFormerKing',
  'isPrivate', 'audience_18plus', 'isAdultContent',
  'ownerIsAdultContent', 'ownerAudience18Plus',
  'allowMessageRequests', 'messageRequestPrivacy', 'groupAddPrivacy',
  'storyReplyPrivacy', 'mentionPrivacy', 'likedVideosPrivacy',
  'favoriteVideosPrivacy', 'whoCanSeeFollowingList', 'isVisitsEnabled',
  'showActivityStatus',
]);
function projectProfile(uid, account) {
  const profile = {uid};
  for (const field of PUBLIC_FIELDS) {
    if (Object.hasOwn(account, field)) profile[field] = account[field];
  }
  // An activity opt-out must not expose the underlying presence timestamps.
  if (account.showActivityStatus !== false) {
    for (const field of ['isOnline', 'lastSeen']) {
      if (Object.hasOwn(account, field)) profile[field] = account[field];
    }
  }
  return profile;
}
async function syncProfile(db, uid) {
  return db.runTransaction(async tx => {
    const source = await tx.get(db.doc(`users/${uid}`));
    const ref = db.doc(`public_profiles/${uid}`);
    const current = await tx.get(ref);
    // Read current source inside the transaction; delayed/retried events cannot
    // overwrite a newer profile or resurrect a deleted account.
    if (!source.exists) {
      if (current.exists) tx.delete(ref);
      return;
    }
    const profile = projectProfile(uid, source.data());
    if (!current.exists || !isDeepStrictEqual(current.data(), profile)) {
      tx.set(ref, profile); // Replace, rather than merge, to remove stale fields.
    }
  });
}
exports.syncPublicProfile = onDocumentWritten({
  region: 'europe-west1', document: 'users/{uid}', retry: true,
}, event => syncProfile(getFirestore(), event.params.uid));
// Repair a legacy/missing public projection when a follow notification opens it.
// The caller cannot supply profile fields, and receives no private account data.
exports.ensureNotificationProfile = onCall({region: 'europe-west1'}, async request => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in required.');
  const uid = request.data?.uid;
  if (typeof uid !== 'string' || !uid.trim() || uid.length > 128 || uid.includes('/')) {
    throw new HttpsError('invalid-argument', 'A valid user ID is required.');
  }
  await syncProfile(getFirestore(), uid);
  return {ok: true};
});
Object.defineProperty(exports, 'testing', {value: {PUBLIC_FIELDS, projectProfile, syncProfile}});