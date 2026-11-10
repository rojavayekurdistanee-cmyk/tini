'use strict';
const {getFirestore, Timestamp} = require('firebase-admin/firestore');
const {onCall} = require('firebase-functions/v2/https');
const {onSchedule} = require('firebase-functions/v2/scheduler');
const {randomUUID} = require('node:crypto');
const {core: {wallet, whole, spendable, identity, enabled, entry, fail, options}} = require('./wallet');
const DAY = 86400000;
const stamp = value => value?.toMillis?.() ?? 0;
function id(value) {
  if (typeof value !== 'string' || !/^[\w-]{1,128}$/.test(value)) fail('invalid-argument', 'معرف غير صالح');
  return value;
}
async function reserve(db, uid, data, admin = false, clock = Date.now) {
  const postId = id(data.postId), requestId = id(data.requestId), token = randomUUID();
  return db.runTransaction(async tx => {
    await enabled(tx, db);
    const receipt = db.doc(`wallet_requests/${uid}/boxes/${requestId}`);
    const previous = (await tx.get(receipt)).data();
    if (previous) {
      if (previous.postId !== postId) fail('already-exists', 'طلب مستخدم لصندوق آخر');
      const hold = (await tx.get(db.doc(`box_holds/${postId}`))).data();
      return {...previous.result, status: hold?.requestId === requestId ? hold.status : 'superseded'};
    }
    const ref = db.doc(`posts/${postId}`), holdRef = db.doc(`box_holds/${postId}`);
    const post = (await tx.get(ref)).data();
    const hold = (await tx.get(holdRef)).data();
    const userRef = db.doc(`users/${uid}`);
    const user = wallet((await tx.get(userRef)).data());
    if (!post || post.isMysteryBox !== true || post.isDeleted === true || post.boxSold || post.boxOwnedByUid || hold?.status === 'held')
      fail('failed-precondition', 'الصندوق غير متاح');
    if (!post.uid || post.uid === uid) fail('failed-precondition', 'لا يمكنك شراء صندوقك');
    // Financial authorization never uses users.isAdmin, which was client-writable.
    const price = admin ? 0 : whole(post.boxPrice);
    if (!admin && price < 1) fail('failed-precondition', 'سعر الصندوق غير صالح');
    if (!['bronze', 'silver', 'gold', 'diamond'].includes(post.boxRarity)) fail('failed-precondition', 'ندرة غير صالحة');
    // Match existing account/video age restrictions and privacy before committing money.
    const seller = (await tx.get(db.doc(`users/${post.uid}`))).data();
    if (!seller) fail('not-found', 'البائع غير موجود');
    wallet(seller);
    const following = await tx.get(db.doc(`users/${post.uid}/followers/${uid}`));
    const mutual = await tx.get(db.doc(`users/${uid}/followers/${post.uid}`));
    const blocked = await tx.get(db.doc(`users/${post.uid}/blockedUsers/${uid}`));
    const blockedBack = await tx.get(db.doc(`users/${uid}/blockedUsers/${post.uid}`));
    if (blocked.exists || blockedBack.exists || (user.blockedUsers ?? []).includes(post.uid) || (seller.blockedUsers ?? []).includes(uid) || ['private','only_me'].includes(post.privacy) ||
        (post.privacy === 'friends' && !(following.exists && mutual.exists)) ||
        (seller.isPrivate === true && !following.exists)) fail('permission-denied', 'الصندوق غير متاح لهذا الحساب');
    const restricted = [post.isAgeRestricted, post.isAdultContent, post.audience_18plus,
      seller.audience_18plus, seller.isAdultContent].some(v => v === true || v === 1 || v === 'true');
    const birth = user.birthDate ?? user.dob;
    const date = birth?.toDate?.() ?? new Date(typeof birth === 'string' ? birth : NaN);
    const today = new Date(clock());
    const adult = Number.isFinite(date.getTime()) && date <= new Date(today.getFullYear() - 18, today.getMonth(), today.getDate());
    if (restricted && !adult) fail('permission-denied', 'الصندوق مخصص للبالغين');
    if (spendable(user) < price) fail('resource-exhausted', 'نقاطك لا تكفي');
    const now = clock(), expiresAt = Timestamp.fromMillis(now + 600000);
    tx.update(userRef, {tiniBalance: user.tiniBalance - price, boxReservedPoints: whole(user.boxReservedPoints + price)});
    tx.set(holdRef, {status: 'held', uid, seller: post.uid, amount: price, requestId,
      token, rarity: post.boxRarity, expiresAt});
    tx.update(ref, {boxOwnedByUid: uid, boxOwnedByName: user.fullName ?? user.username ?? '',
      boxReservedAt: Timestamp.fromMillis(now), boxExpiresAt: expiresAt, boxSecureHash: token});
    entry(tx, db, uid, `box_${requestId}_hold`, 'box_reserve', price, {postId});
    const result = {token, requestId, status: 'held'};
    tx.create(receipt, {postId, result});
    return result;
  });
}
async function finish(db, uid, data, action, clock = Date.now) {
  const postId = id(data.postId);
  return db.runTransaction(async tx => {
    // Refunds remain possible while purchases are paused; migration freezes all writes.
    const cfg = (await tx.get(db.doc('wallet_config/runtime'))).data();
    if (cfg?.migrationInProgress) fail('failed-precondition', 'انتقال المحفظة جار');
    const holdRef = db.doc(`box_holds/${postId}`), ref = db.doc(`posts/${postId}`);
    const hold = (await tx.get(holdRef)).data();
    const postExists = (await tx.get(ref)).exists;
    if (!hold || (uid && (hold.uid !== uid || data.token !== hold.token))) fail('permission-denied', 'الحجز غير صالح');
    if (hold.status !== 'held') return {completed: hold.status === 'sold'};
    const now = clock(), expired = stamp(hold.expiresAt) <= now;
    if (action === 'expire' && !expired) return {completed: false};
    const buying = action === 'buy' && !expired && postExists;
    if (buying && cfg?.enabled !== true) fail('failed-precondition', 'الشراء متوقف مؤقتاً');
    const buyerRef = db.doc(`users/${hold.uid}`);
    const buyer = wallet((await tx.get(buyerRef)).data());
    const sellerRef = db.doc(`users/${hold.seller}`);
    const seller = buying ? wallet((await tx.get(sellerRef)).data()) : null;
    if (buyer.boxReservedPoints < hold.amount) fail('failed-precondition', 'الحجز يحتاج إلى مراجعة');
    if (buying && buyer.walletDebt) fail('failed-precondition', 'توجد تسوية معلقة');
    const refundDebtPaid = buying ? 0 : Math.min(buyer.walletDebt ?? 0, hold.amount);
    tx.update(buyerRef, {boxReservedPoints: buyer.boxReservedPoints - hold.amount,
      ...(!buying ? {tiniBalance: whole(buyer.tiniBalance + hold.amount - refundDebtPaid), walletDebt: (buyer.walletDebt ?? 0) - refundDebtPaid} : {})});
    if (buying) {
      const debtPaid = Math.min(seller.walletDebt ?? 0, hold.amount);
      tx.update(sellerRef, {tiniBalance: whole(seller.tiniBalance + hold.amount - debtPaid),
        walletDebt: (seller.walletDebt ?? 0) - debtPaid});
      entry(tx, db, hold.seller, `box_${hold.requestId}_sale`, 'box_sale', hold.amount, {postId, debtPaid});
      const powers = {diamond: 4, gold: 3, silver: 2, bronze: 1};
      const badge = (powers[buyer.badge] ?? 0) > powers[hold.rarity] ? buyer.badge : hold.rarity;
      tx.update(buyerRef, {badge, badgeEndsAt: Timestamp.fromMillis(Math.max(now, stamp(buyer.badgeEndsAt)) + 7 * DAY)});
      tx.update(ref, {boxSold: true, boxSoldAt: Timestamp.fromMillis(now), boxOpenedAt: Timestamp.fromMillis(now), boxExpiresAt: null});
    } else {
      if (postExists) tx.update(ref, {boxOwnedByUid: null, boxOwnedByName: null, boxReservedAt: null, boxExpiresAt: null, boxSecureHash: null});
    }
    tx.update(holdRef, {status: buying ? 'sold' : 'refunded', expiresAt: null, endedAt: Timestamp.fromMillis(now)});
    entry(tx, db, hold.uid, `box_${hold.requestId}_end`, buying ? 'box_settle' : 'box_refund', hold.amount, {postId, debtPaid: refundDebtPaid});
    return {completed: buying};
  });
}
exports.reserveTiniBox = onCall(options, request => reserve(getFirestore(), identity(request), request.data, request.auth.token.admin === true));
exports.confirmTiniBox = onCall(options, request => finish(getFirestore(), identity(request), request.data, 'buy'));
exports.cancelTiniBox = onCall(options, request => finish(getFirestore(), identity(request), request.data, 'cancel'));
exports.expireTiniBoxes = onSchedule({region: options.region, schedule: 'every 1 minutes', retryCount: 3}, async () => {
  const db = getFirestore();
  // A single-field timestamp query uses the automatic index; terminal holds clear expiresAt.
  const holds = await db.collection('box_holds').where('expiresAt', '<=', Timestamp.now()).limit(200).get();
  for (const doc of holds.docs) if (stamp(doc.data().expiresAt) <= Date.now())
    await finish(db, null, {postId: doc.id}, 'expire');
});
Object.defineProperty(exports, 'testing', {value: {reserve, finish}});