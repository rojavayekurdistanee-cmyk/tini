'use strict';
const {getFirestore, Timestamp} = require('firebase-admin/firestore');
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {core: {wallet, whole, identity, enabled, entry, fail, options}} = require('./wallet');
const {verify, PRODUCTS} = require('./purchase_verifier');
async function deliver(db, uid, verified) {
  if (!Object.hasOwn(PRODUCTS, verified.productId) || !/^[a-f0-9]{64}$/.test(verified.id))
    fail('invalid-argument', 'فاتورة غير صالحة');
  return db.runTransaction(async tx => {
    const config = await enabled(tx, db);
    if (config.purchasesEnabled !== true || (verified.sandbox && !config.allowSandbox))
      fail('failed-precondition', 'الشراء غير مفعل');
    const receipt = db.doc(`wallet_receipts/${verified.id}`);
    const prior = await tx.get(receipt);
    if (prior.data()?.revoked) fail('failed-precondition', 'تم استرجاع هذه الفاتورة');
    if (prior.data()?.uid) {
      if (prior.data().uid !== uid || prior.data().productId !== verified.productId)
        fail('already-exists', 'تم تسليم هذه الفاتورة لحساب آخر');
      return {delivered: true, duplicate: true};
    }
    const ref = db.doc(`users/${uid}`);
    const user = wallet((await tx.get(ref)).data());
    const amount = PRODUCTS[verified.productId];
    const debtPaid = Math.min(user.walletDebt ?? 0, amount);
    const balance = whole(user.tiniBalance + amount - debtPaid);
    tx.update(ref, {tiniBalance: balance, walletDebt: (user.walletDebt ?? 0) - debtPaid});
    tx.set(receipt, {...verified, uid, amount, revoked: false, deliveredAt: Timestamp.now()}, {merge: true});
    entry(tx, db, uid, `purchase_${verified.id}`, 'purchase', amount,
      {packageId: verified.productId, debtPaid, balanceAfter: balance, sandbox: verified.sandbox});
    return {delivered: true, duplicate: false};
  });
}
exports.verifyTiniPurchase = onCall(options, async request => {
  const uid = identity(request), db = getFirestore();
  const config = (await db.doc('wallet_config/runtime').get()).data();
  if (config?.purchasesEnabled !== true || config.enabled !== true || config.migrationInProgress)
    fail('failed-precondition', 'الشراء غير مفعل بعد');
  const user = wallet((await db.doc(`users/${uid}`).get()).data());
  let verified;
  try { verified = await verify(request.data, user.purchaseAccountToken, config); }
  catch (e) {
    if (e instanceof HttpsError) throw e;
    fail('unavailable', 'تعذر تأكيد الفاتورة من المتجر؛ أعد المحاولة');
  }
  return deliver(db, uid, verified);
});
// Privileged reconciliation only: verified store refunds use the same global receipt.
async function revoke(db, receiptId, eventTime = null) {
  return db.runTransaction(async tx => {
    const cfg = (await tx.get(db.doc('wallet_config/runtime'))).data();
    if (cfg?.migrationInProgress) fail('unavailable', 'Migration in progress');
    const ref = db.doc(`wallet_receipts/${receiptId}`);
    const receipt = (await tx.get(ref)).data();
    if (eventTime != null && (receipt?.lastStoreEventAt ?? 0) > eventTime) return {applied: false};
    if (!receipt?.uid) {
      tx.set(ref, {revoked: true, revocationCount: 1, revokedAt: Timestamp.now(), ...(eventTime != null ? {lastStoreEventAt: eventTime} : {})}, {merge: true});
      return {applied: true};
    }
    if (receipt.revoked) {
      if (eventTime != null) tx.update(ref, {lastStoreEventAt: eventTime});
      return {applied: false};
    }
    const userRef = db.doc(`users/${receipt.uid}`);
    const user = wallet((await tx.get(userRef)).data());
    const debit = Math.min(user.tiniBalance, receipt.amount);
    tx.update(userRef, {tiniBalance: user.tiniBalance - debit,
      walletDebt: whole((user.walletDebt ?? 0) + receipt.amount - debit)});
    const sequence = (receipt.revocationCount ?? 0) + 1;
    tx.update(ref, {revoked: true, revocationCount: sequence, revokedAt: Timestamp.now(), ...(eventTime != null ? {lastStoreEventAt: eventTime} : {})});
    entry(tx, db, receipt.uid, `revoke_${receiptId}_${sequence}`, 'chargeback', receipt.amount);
    return {applied: true};
  });
}
async function reverseRefund(db, receiptId, eventTime = null) {
  return db.runTransaction(async tx => {
    const cfg = (await tx.get(db.doc('wallet_config/runtime'))).data();
    if (cfg?.migrationInProgress) fail('unavailable', 'Migration in progress');
    const ref = db.doc(`wallet_receipts/${receiptId}`);
    const receipt = (await tx.get(ref)).data();
    if (eventTime != null && (receipt?.lastStoreEventAt ?? 0) > eventTime) return {applied: false};
    if (!receipt?.revoked) {
      if (eventTime != null) tx.set(ref, {lastStoreEventAt: eventTime, revoked: false}, {merge: true});
      return {applied: false};
    }
    if (!receipt.uid) { tx.update(ref, {revoked: false, ...(eventTime != null ? {lastStoreEventAt: eventTime} : {})}); return {applied: true}; }
    const userRef = db.doc(`users/${receipt.uid}`);
    const user = wallet((await tx.get(userRef)).data());
    const debtPaid = Math.min(user.walletDebt ?? 0, receipt.amount);
    tx.update(userRef, {tiniBalance: whole(user.tiniBalance + receipt.amount - debtPaid),
      walletDebt: (user.walletDebt ?? 0) - debtPaid});
    tx.update(ref, {revoked: false, reversedAt: Timestamp.now(), ...(eventTime != null ? {lastStoreEventAt: eventTime} : {})});
    entry(tx, db, receipt.uid, `reverse_${receiptId}_${receipt.revocationCount}`, 'refund_reversed', receipt.amount, {debtPaid});
    return {applied: true};
  });
}
Object.defineProperty(exports, 'testing', {value: {deliver, revoke, reverseRefund}});
