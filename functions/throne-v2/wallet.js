'use strict';
const {getFirestore, Timestamp} = require('firebase-admin/firestore');
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {randomUUID} = require('node:crypto');
const options = {region: 'europe-west1', enforceAppCheck: true};
function fail(code, message) { throw new HttpsError(code, message); }
function whole(n) {
  if (!Number.isSafeInteger(n) || n < 0) fail('failed-precondition', 'رصيد المحفظة يحتاج إلى مراجعة');
  return n;
}
function wallet(data) {
  if (data?.walletVersion !== 2) fail('failed-precondition', 'المحفظة بانتظار التهيئة الآمنة');
  whole(data.tiniBalance); whole(data.throneReservedPoints); whole(data.boxReservedPoints);
  whole(data.walletDebt ?? 0);
  return data;
}
function spendable(data) {
  wallet(data);
  if (data.walletDebt) fail('failed-precondition', 'توجد تسوية معلقة على المحفظة');
  return data.tiniBalance;
}
function identity(request) {
  if (!request.auth || request.data?.uid !== request.auth.uid)
    fail('unauthenticated', 'تغير الحساب؛ أعد تسجيل الدخول');
  return request.auth.uid;
}
async function enabled(tx, db) {
  const config = (await tx.get(db.doc('wallet_config/runtime'))).data();
  if (config?.version !== 2 || config?.enabled !== true || config?.migrationInProgress)
    fail('failed-precondition', 'المحفظة غير متاحة مؤقتاً');
  return config;
}
function entry(tx, db, uid, id, type, amount, extra = {}) {
  tx.create(db.doc(`users/${uid}/transactions/${id}`), {
    type, amount: whole(amount), createdAt: Timestamp.now(), ...extra,
  });
}
async function create(db, uid) {
  const accountToken = randomUUID();
  return db.runTransaction(async tx => {
    await enabled(tx, db);
    const ref = db.doc(`users/${uid}`);
    const snapshot = await tx.get(ref);
    if (!snapshot.exists) fail('not-found', 'أنشئ الملف الشخصي أولاً');
    const data = snapshot.data();
    if (data.walletVersion === 2) {
      wallet(data);
      return {balance: data.tiniBalance, accountToken: data.purchaseAccountToken};
    }
    const old = await tx.get(db.doc(`throne_wallets/${uid}`));
    // Existing money is never guessed or copied by an ordinary callable.
    if (old.exists || (data.tiniBalance ?? 0) !== 0 || (data.throneReservedPoints ?? 0) !== 0)
      fail('failed-precondition', 'الحساب القديم يحتاج إلى أداة الانتقال');
    tx.update(ref, {walletVersion: 2, tiniBalance: 0, throneReservedPoints: 0,
      boxReservedPoints: 0, walletDebt: 0, purchaseAccountToken: accountToken});
    return {balance: 0, accountToken};
  });
}
exports.createTiniWallet = onCall(options, request => create(getFirestore(), identity(request)));
Object.defineProperty(exports, 'testing', {value: {create}});
Object.defineProperty(exports, 'core', {value: {wallet, whole, spendable, identity, enabled, entry, fail, options}});