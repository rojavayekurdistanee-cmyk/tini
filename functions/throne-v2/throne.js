"use strict";
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {onDocumentUpdated} = require("firebase-functions/v2/firestore");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {getFirestore, Timestamp, FieldValue} = require("firebase-admin/firestore");
const {randomUUID} = require("node:crypto");
const {core: {wallet: validateWallet, spendable, enabled: walletEnabled, entry}} = require('./wallet');
const userRef = (db, uid, unified) => db.doc(`${unified ? 'users' : 'throne_wallets'}/${uid}`);
const held = (w, unified) => unified ? w?.throneReservedPoints : w?.reservedPoints;
const DAY = 86400000;
const options = {region: "europe-west1", enforceAppCheck: true};
const fail = (code, message) => { throw new HttpsError(code, message); };
const millis = value => value?.toMillis?.() ?? 0;
function auth(request) {
  if (!request.auth) fail("unauthenticated", "يجب تسجيل الدخول");
  return request.auth.uid;
}
function identifier(value) {
  if (typeof value !== "string" || !/^[a-zA-Z0-9_-]{1,128}$/.test(value))
    fail("invalid-argument", "معرّف الطلب غير صالح");
  return value;
}
function auction(id, now, unified = false) {
  return {schemaVersion: 3, walletVersion: unified ? 2 : 1, status: "auction", auctionId: id,
    auctionStartsAt: Timestamp.fromMillis(now), auctionEndsAt: Timestamp.fromMillis(now + DAY),
    currentBid: 0, leaderUid: null, leaderName: null, leaderAvatar: null,
    kingUid: null, kingName: null, kingAvatar: null, isLocked: false,
    reignStartsAt: null, lockEndTime: null, coronationId: null, reactions: {crown: 0, heart: 0, fire: 0}};
}
function crown(tx, db, state, entitlement, now, instant) {
  const id = state.auctionId;
  const end = now + (instant ? 7 : 1) * DAY;
  const count = (entitlement?.coronationCount ?? 0) + 1;
  if (!Number.isSafeInteger(count) || count < 1)
    fail('failed-precondition', 'سجل التتويج يحتاج إلى مراجعة');
  const record = {uid: state.leaderUid, name: state.leaderName, avatar: state.leaderAvatar,
    coronationId: id, auctionId: id, crownedAt: Timestamp.fromMillis(now),
    endsAt: Timestamp.fromMillis(end), durationMs: end - now, winningBid: state.currentBid,
    coronationCount: count, completed: false};
  tx.create(db.doc(`throne_reigns/${id}`), record);
  tx.set(db.doc(`throne_entitlements/${state.leaderUid}`), {
    currentCoronationId: id, currentUntil: record.endsAt, coronationCount: count,
    formerKing: entitlement?.formerKing === true});
  const unified = state.walletVersion === 2;
  tx.update(userRef(db, state.leaderUid, unified), unified ? {throneReservedPoints: 0} : {reservedPoints: 0});
  if (unified) entry(tx, db, state.leaderUid, `${id}_settle`, 'throne_settle', state.currentBid);
  tx.create(db.doc(`throne_ledger/${id}_settle`), {
    uid: state.leaderUid, amount: state.currentBid, type: "settle", auctionId: id,
    timestamp: Timestamp.fromMillis(now)});
  return {...state, status: "reign", kingUid: state.leaderUid, kingName: state.leaderName,
    kingAvatar: state.leaderAvatar, isLocked: true, reignStartsAt: record.crownedAt,
    lockEndTime: record.endsAt, coronationId: id, auctionEndsAt: null,
    reactions: {crown: 0, heart: 0, fire: 0}};
}
// One transaction serializes all state transitions against the singleton document.
async function advance(db = getFirestore(), clock = Date.now) {
  const nextId = randomUUID();
  return db.runTransaction(async tx => {
    const ref = db.doc("throne_data/current");
    const snap = await tx.get(ref);
    const state = snap.data();
    const migration = (await tx.get(db.doc('wallet_config/runtime'))).data();
    if (migration?.migrationInProgress) return;
    const now = clock();
    if (!state) {
      const config = (await tx.get(db.doc('throne_config/runtime'))).data();
      if (config?.enabled === true && config?.financialSafetyVersion === 3)
        tx.set(ref, auction(nextId, now, state?.walletVersion === 2 || migration?.version === 2));
      return;
    }
    // Older schemas use another point source. Never migrate them or copy balances implicitly.
    if (state.schemaVersion !== 3) return;
    if (state.status === "auction" && millis(state.auctionEndsAt) <= now) {
      if (!state.leaderUid) { tx.set(ref, auction(nextId, now, state?.walletVersion === 2 || migration?.version === 2)); return; }
      const wallet = await tx.get(userRef(db, state.leaderUid, state.walletVersion === 2));
      if (!wallet.exists || held(wallet.data(), state.walletVersion === 2) !== state.currentBid)
        fail("failed-precondition", "حجز غير متطابق؛ يلزم تدخل المشرف");
      if (state.walletVersion === 2) validateWallet(wallet.data());
      const entitlement = (await tx.get(db.doc(`throne_entitlements/${state.leaderUid}`))).data();
      tx.set(ref, crown(tx, db, state, entitlement, now, false));
    } else if (state.status === "reign" && millis(state.lockEndTime) <= now) {
      tx.set(db.doc(`throne_entitlements/${state.kingUid}`), {
        currentCoronationId: null, currentUntil: null, formerKing: true}, {merge: true});
      tx.update(db.doc(`throne_reigns/${state.coronationId}`), {completed: true});
      tx.set(ref, auction(nextId, now, state?.walletVersion === 2 || migration?.version === 2));
    }
  });
}
async function bid(db, uid, data, clock = Date.now) {
  const requestId = identifier(data?.requestId);
  const auctionId = identifier(data?.auctionId);
  const amount = data?.amount;
  if (!Number.isSafeInteger(amount) || amount < 1 || amount > 10000)
    fail("invalid-argument", "المزايدة بين 1 و10,000 نقطة");
  return db.runTransaction(async tx => {
    let now = clock();
    const receiptRef = db.doc(`throne_requests/${uid}/bids/${requestId}`);
    const receipt = await tx.get(receiptRef);
    if (receipt.exists) {
      const previous = receipt.data();
      if (previous.amount !== amount || previous.auctionId !== auctionId)
        fail("already-exists", "معرّف مستخدم لطلب مختلف");
      return previous.result;
    }
    const config = (await tx.get(db.doc('throne_config/runtime'))).data();
    if (config?.enabled !== true || config?.financialSafetyVersion !== 3)
      fail('failed-precondition', 'المزايدات غير مفعلة؛ يلزم تشغيل إصدار نقاط العرش الآمن');
    await walletEnabled(tx, db);
    const ref = db.doc("throne_data/current");
    const snap = await tx.get(ref);
    const state = snap.data();
    if (state?.walletVersion !== 2) fail('failed-precondition', 'انتقال المحفظة لم يكتمل');
    if (state?.schemaVersion !== 3 || state.status !== "auction" || state.auctionId !== auctionId)
      fail("failed-precondition", "المزاد غير متاح أو تغير");
    if (millis(state.auctionEndsAt) <= now) fail("deadline-exceeded", "انتهى المزاد");
    if (amount <= state.currentBid) fail("out-of-range", "المزايدة يجب أن تكون أعلى");
    const userRef = db.doc(`users/${uid}`);
    const userSnap = await tx.get(userRef);
    if (!userSnap.exists) fail("not-found", "الحساب غير موجود");
    const user = userSnap.data();
    const walletRef = userRef;
    const walletSnap = await tx.get(walletRef);
    const wallet = walletSnap.data();
    validateWallet(wallet);
    const same = state.leaderUid === uid;
    const delta = amount - (same ? state.currentBid : 0);
    const available = spendable(wallet);
    if (available < delta) fail("resource-exhausted", "نقاطك المتاحة لا تكفي");
    const entitlement = (await tx.get(db.doc(`throne_entitlements/${uid}`))).data();
    let oldRef, oldWallet;
    if (state.leaderUid && !same) {
      oldRef = db.doc(`users/${state.leaderUid}`);
      const old = await tx.get(oldRef);
      if (!old.exists || old.data().throneReservedPoints !== state.currentBid)
        fail("failed-precondition", "حجز سابق غير متطابق");
      oldWallet = old.data();
    }
    if ((wallet.throneReservedPoints ?? 0) !== (same ? state.currentBid : 0))
      fail("failed-precondition", "حجز المستخدم غير متطابق");
    // Reads may take time. Check the authoritative clock again before scheduling writes.
    now = clock();
    if (millis(state.auctionEndsAt) <= now) fail('deadline-exceeded', 'انتهى المزاد');
    const ledgerId = `${auctionId}_${uid}_${requestId}`;
    if (oldRef) {
      const old = validateWallet(oldWallet);
      const debtPaid = Math.min(old.walletDebt ?? 0, state.currentBid);
      const refundedBalance = old.tiniBalance + state.currentBid - debtPaid;
      if (!Number.isSafeInteger(refundedBalance)) fail('failed-precondition', 'الرصيد يحتاج إلى مراجعة');
      tx.update(oldRef, {tiniBalance: refundedBalance, throneReservedPoints: 0, walletDebt: (old.walletDebt ?? 0) - debtPaid});
      entry(tx, db, state.leaderUid, `${ledgerId}_refund`, 'throne_refund', state.currentBid, {debtPaid});
      tx.create(db.doc(`throne_ledger/${ledgerId}_refund`), {
        uid: state.leaderUid, amount: state.currentBid, type: "refund", auctionId,
        timestamp: Timestamp.fromMillis(now)});
    }
    tx.update(walletRef, {tiniBalance: available - delta, throneReservedPoints: amount});
    entry(tx, db, uid, `${ledgerId}_reserve`, 'throne_reserve', delta);
    tx.create(db.doc(`throne_ledger/${ledgerId}_reserve`), {
      uid, amount: delta, type: "reserve", auctionId, timestamp: Timestamp.fromMillis(now)});
    const fullName = typeof user.fullName === 'string' ? user.fullName : '';
    const username = typeof user.username === 'string' ? user.username : '';
    let next = {...state, leaderUid: uid, leaderName: (fullName || username || 'مستخدم').slice(0, 200),
      leaderAvatar: typeof user.profileImg === 'string' ? user.profileImg : '', currentBid: amount};
    tx.set(db.doc(`throne_auctions/${auctionId}/competitors/${uid}`), {
      uid, name: next.leaderName, avatar: next.leaderAvatar, amount,
      timestamp: Timestamp.fromMillis(now)});
    tx.create(db.doc(`throne_bids/${ledgerId}`), {
      uid, auctionId, bidAmount: amount, fullName: next.leaderName, timestamp: Timestamp.fromMillis(now)});
    if (amount === 10000) next = crown(tx, db, next, entitlement, now, true);
    tx.set(ref, next);
    const result = {accepted: true, coronationId: next.coronationId, amount};
    tx.create(receiptRef, {amount, auctionId, result});
    return result;
  });
}
// Read the latest profile inside the transaction: event delivery can be out of order.
async function syncProfile(db, uid) {
  return db.runTransaction(async tx => {
    const profile = (await tx.get(db.doc(`users/${uid}`))).data();
    const ref = db.doc('throne_data/current');
    const state = (await tx.get(ref)).data();
    if (!profile || state?.schemaVersion !== 3) return;
    const fullName = typeof profile.fullName === 'string' ? profile.fullName : '';
    const username = typeof profile.username === 'string' ? profile.username : '';
    const name = (fullName || username || 'مستخدم').slice(0, 200);
    const avatar = typeof profile.profileImg === 'string' ? profile.profileImg : '';
    const competitorRef = state.auctionId
      ? db.doc(`throne_auctions/${state.auctionId}/competitors/${uid}`) : null;
    const competitor = competitorRef ? await tx.get(competitorRef) : null;
    const patch = {};
    for (const role of ['king', 'leader']) {
      if (state[`${role}Uid`] === uid) {
        if (state[`${role}Name`] !== name) patch[`${role}Name`] = name;
        if (state[`${role}Avatar`] !== avatar) patch[`${role}Avatar`] = avatar;
      }
    }
    if (Object.keys(patch).length) tx.update(ref, patch);
    if (competitor?.exists &&
        (competitor.data().name !== name || competitor.data().avatar !== avatar)) {
      tx.update(competitorRef, {name, avatar});
    }
  });
}
exports.syncThroneProfile = onDocumentUpdated({
  region: options.region, document: 'users/{uid}', retry: true,
}, event => {
  const before = event.data.before.data();
  const after = event.data.after.data();
  if (['fullName', 'username', 'profileImg'].every(key => before[key] === after[key])) return;
  return syncProfile(getFirestore(), event.params.uid);
});
exports.placeThroneBid = onCall(options, async request => {
  const uid = auth(request);
  if (request.data?.uid !== uid) fail('unauthenticated', 'تغير الحساب؛ أعد المحاولة');
  await advance();
  return bid(getFirestore(), uid, request.data);
});
function availability(config, walletConfig, state) {
  let reason = null;
  if (walletConfig?.migrationInProgress) reason = 'wallet_migration_in_progress';
  else if (walletConfig?.version !== 2) reason = 'wallet_migration_required';
  else if (walletConfig?.enabled !== true) reason = 'wallet_disabled';
  else if (config?.financialSafetyVersion !== 3) reason = 'throne_activation_required';
  else if (config?.enabled !== true) reason = 'throne_disabled';
  else if (state?.schemaVersion !== 3) reason = 'throne_schema_required';
  else if (state?.walletVersion !== 2) reason = 'throne_wallet_migration_required';
  return {enabled: reason === null, availabilityReason: reason};
}
exports.syncThrone = onCall(options, async request => {
  auth(request);
  const db = getFirestore();
  await advance();
  const status = await db.runTransaction(async tx => {
    const config = (await tx.get(db.doc('throne_config/runtime'))).data();
    const wc = (await tx.get(db.doc('wallet_config/runtime'))).data();
    const state = (await tx.get(db.doc('throne_data/current'))).data();
    return availability(config, wc, state);
  });
  return {serverNow: Date.now(), ...status};
});
exports.advanceThrone = onSchedule({region: options.region, schedule: "every 1 minutes", retryCount: 3}, () => advance());
async function react(db, uid, data, clock = Date.now) {
  const id = identifier(data?.coronationId);
  const kind = data?.kind;
  if (!["crown", "heart", "fire"].includes(kind)) fail("invalid-argument", "تفاعل غير صالح");
  return db.runTransaction(async tx => {
    const ref = db.doc("throne_data/current");
    const state = (await tx.get(ref)).data();
    const cfg = (await tx.get(db.doc('wallet_config/runtime'))).data();
    if (cfg?.migrationInProgress) fail('unavailable', 'انتقال المحفظة جار');
    const reactionRef = db.doc(`throne_reigns/${id}/reactions/${uid}`);
    const old = await tx.get(reactionRef);
    if (state?.status !== "reign" || state.coronationId !== id || millis(state.lockEndTime) <= clock())
      fail("failed-precondition", "انتهت فترة الحكم");
    // One immutable choice per user per reign: retries are free and cannot inflate counts.
    if (old.exists) return {accepted: true, kind: old.data().kind};
    tx.create(reactionRef, {kind});
    tx.update(ref, {[`reactions.${kind}`]: FieldValue.increment(1)});
    tx.update(db.doc(`throne_reigns/${id}`), {[`reactions.${kind}`]: FieldValue.increment(1)});
    return {accepted: true, kind};
  });
}
exports.reactToThrone = onCall(options, request => react(getFirestore(), auth(request), request.data));
// Test hooks are non-enumerable so Firebase never discovers them as functions.
Object.defineProperty(exports, "testing", {value: {auction, bid, advance, react, syncProfile, availability, DAY}});
