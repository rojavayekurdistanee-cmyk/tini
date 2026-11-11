'use strict';
const {getFirestore} = require('firebase-admin/firestore');
const {onDocumentWritten} = require('firebase-functions/v2/firestore');
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
Object.defineProperty(exports, 'testing', {value: {PUBLIC_FIELDS, projectProfile, syncProfile}});
