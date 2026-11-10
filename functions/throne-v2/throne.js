"use strict";
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {getFirestore, Timestamp, FieldValue} = require("firebase-admin/firestore");
const {randomUUID} = require("node:crypto");
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
function balance(wallet) {
  const n = wallet?.availablePoints ?? 0;
  if (!Number.isSafeInteger(n) || n < 0) fail("failed-precondition", "الرصيد يحتاج إلى مراجعة");
  return n;
}
function auction(id, now) {
  return {schemaVersion: 3, status: "auction", auctionId: id,
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
  tx.update(db.doc(`throne_wallets/${state.leaderUid}`), {reservedPoints: 0});
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
    const now = clock();
    if (!state) {
      const config = (await tx.get(db.doc('throne_config/runtime'))).data();
      if (config?.enabled === true && config?.financialSafetyVersion === 3)
        tx.set(ref, auction(nextId, now));
      return;
    }
    // Older schemas use another point source. Never migrate them or copy balances implicitly.
    if (state.schemaVersion !== 3) return;
    if (state.status === "auction" && millis(state.auctionEndsAt) <= now) {
      if (!state.leaderUid) { tx.set(ref, auction(nextId, now)); return; }
      const wallet = await tx.get(db.doc(`throne_wallets/${state.leaderUid}`));
      if (!wallet.exists || wallet.data().reservedPoints !== state.currentBid)
        fail("failed-precondition", "حجز غير متطابق؛ يلزم تدخل المشرف");
      const entitlement = (await tx.get(db.doc(`throne_entitlements/${state.leaderUid}`))).data();
      tx.set(ref, crown(tx, db, state, entitlement, now, false));
    } else if (state.status === "reign" && millis(state.lockEndTime) <= now) {
      tx.set(db.doc(`throne_entitlements/${state.kingUid}`), {
        currentCoronationId: null, currentUntil: null, formerKing: true}, {merge: true});
      tx.update(db.doc(`throne_reigns/${state.coronationId}`), {completed: true});
      tx.set(ref, auction(nextId, now));
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
    const ref = db.doc("throne_data/current");
    const snap = await tx.get(ref);
    const state = snap.data();
    if (state?.schemaVersion !== 3 || state.status !== "auction" || state.auctionId !== auctionId)
      fail("failed-precondition", "المزاد غير متاح أو تغير");
    if (millis(state.auctionEndsAt) <= now) fail("deadline-exceeded", "انتهى المزاد");
    if (amount <= state.currentBid) fail("out-of-range", "المزايدة يجب أن تكون أعلى");
    const userRef = db.doc(`users/${uid}`);
    const userSnap = await tx.get(userRef);
    if (!userSnap.exists) fail("not-found", "الحساب غير موجود");
    const user = userSnap.data();
    const walletRef = db.doc(`throne_wallets/${uid}`);
    const walletSnap = await tx.get(walletRef);
    const wallet = walletSnap.data();
    if (!wallet || wallet.schemaVersion !== 1) fail('failed-precondition', 'نقاط العرش غير مهيأة؛ أعد المزامنة');
    const same = state.leaderUid === uid;
    const delta = amount - (same ? state.currentBid : 0);
    const available = balance(wallet);
    if (available < delta) fail("resource-exhausted", "نقاطك المتاحة لا تكفي");
    const entitlement = (await tx.get(db.doc(`throne_entitlements/${uid}`))).data();
    let oldRef, oldWallet;
    if (state.leaderUid && !same) {
      oldRef = db.doc(`throne_wallets/${state.leaderUid}`);
      const old = await tx.get(oldRef);
      if (!old.exists || old.data().reservedPoints !== state.currentBid)
        fail("failed-precondition", "حجز سابق غير متطابق");
      oldWallet = old.data();
    }
    if ((wallet.reservedPoints ?? 0) !== (same ? state.currentBid : 0))
      fail("failed-precondition", "حجز المستخدم غير متطابق");
    // Reads may take time. Check the authoritative clock again before scheduling writes.
    now = clock();
    if (millis(state.auctionEndsAt) <= now) fail('deadline-exceeded', 'انتهى المزاد');
    const ledgerId = `${auctionId}_${uid}_${requestId}`;
    if (oldRef) {
      const refundedBalance = balance(oldWallet) + state.currentBid;
      if (!Number.isSafeInteger(refundedBalance)) fail('failed-precondition', 'الرصيد يحتاج إلى مراجعة');
      tx.update(oldRef, {availablePoints: refundedBalance, reservedPoints: 0});
      tx.create(db.doc(`throne_ledger/${ledgerId}_refund`), {
        uid: state.leaderUid, amount: state.currentBid, type: "refund", auctionId,
        timestamp: Timestamp.fromMillis(now)});
    }
    tx.update(walletRef, {availablePoints: available - delta, reservedPoints: amount});
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
exports.placeThroneBid = onCall(options, async request => {
  const uid = auth(request);
  if (request.data?.uid !== uid) fail('unauthenticated', 'تغير الحساب؛ أعد المحاولة');
  await advance();
  return bid(getFirestore(), uid, request.data);
});
exports.syncThrone = onCall(options, async request => {
  const uid = auth(request);
  const db = getFirestore();
  await db.runTransaction(async tx => {
    const ref = db.doc(`throne_wallets/${uid}`);
    const wallet = await tx.get(ref);
    const user = await tx.get(db.doc(`users/${uid}`));
    if (!wallet.exists && user.exists) tx.create(ref, {schemaVersion: 1, availablePoints: 0, reservedPoints: 0});
  });
  await advance();
  const config = (await getFirestore().doc('throne_config/runtime').get()).data();
  return {serverNow: Date.now(), enabled: config?.enabled === true && config?.financialSafetyVersion === 3};
});
exports.advanceThrone = onSchedule({region: options.region, schedule: "every 1 minutes", retryCount: 3}, () => advance());
async function react(db, uid, data, clock = Date.now) {
  const id = identifier(data?.coronationId);
  const kind = data?.kind;
  if (!["crown", "heart", "fire"].includes(kind)) fail("invalid-argument", "تفاعل غير صالح");
  return db.runTransaction(async tx => {
    const ref = db.doc("throne_data/current");
    const state = (await tx.get(ref)).data();
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
Object.defineProperty(exports, "testing", {value: {auction, bid, advance, react, DAY}});