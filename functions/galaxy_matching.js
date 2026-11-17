'use strict';
const {getFirestore} = require('firebase-admin/firestore');
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {onDocumentWritten} = require('firebase-functions/v2/firestore');
const {onSchedule} = require('firebase-functions/v2/scheduler');
const {isDeepStrictEqual} = require('node:util');
const {createMatching} = require('./galaxy_matching_core');
const region = 'europe-west1';
const core = () => createMatching(getFirestore());
function callable(method) {
  return onCall({region, maxInstances: 10, timeoutSeconds: 60}, async request => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'سجّل الدخول أولاً.');
    return core()[method](request.auth.uid, request.data || {});
  });
}
exports.saveGalaxyMatchPreferences = callable('save');
exports.discoverGalaxyMatches = callable('discover');
exports.requestGalaxyMatch = callable('request');
exports.respondGalaxyMatch = callable('respond');
exports.manageGalaxyMatch = callable('manage');
const relevant = ['fullName', 'username', 'isPrivate', 'showInGalaxy', 'birthDate', 'dob',
  'audience_18plus', 'isAdultContent', 'ownerIsAdultContent', 'ownerAudience18Plus', 'blockedUsers', 'blocked'];
exports.syncGalaxyMatchEligibility = onDocumentWritten({region, document: 'users/{uid}', retry: true, timeoutSeconds: 300, maxInstances: 10}, async event => {
  const before = event.data?.before.data(), after = event.data?.after.data();
  if (before && after && relevant.every(k => isDeepStrictEqual(before[k], after[k]))) return;
  await core().sync(event.params.uid);
});
exports.syncGalaxyMatchPreferences = onDocumentWritten({region, document: 'galaxy_match_preferences/{uid}', retry: true, timeoutSeconds: 300, maxInstances: 10}, async event => {
  if (isDeepStrictEqual(event.data?.before.data(), event.data?.after.data())) return;
  await core().sync(event.params.uid);
});
exports.syncGalaxyMatchBlocks = onDocumentWritten({region, document: 'users/{uid}/blocked/{peer}', retry: true, timeoutSeconds: 300, maxInstances: 10}, async event => {
  await core().sync(event.params.uid, event.params.peer);
});
exports.cleanupGalaxyMatches = onSchedule({region, schedule: 'every 60 minutes', timeZone: 'UTC', timeoutSeconds: 300, maxInstances: 1},
  () => core().cleanup());