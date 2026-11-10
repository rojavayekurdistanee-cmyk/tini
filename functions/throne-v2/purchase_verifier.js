'use strict';
const {GoogleAuth} = require('google-auth-library');
const {SignedDataVerifier, Environment} = require('@apple/app-store-server-library');
const {createHash} = require('node:crypto');
const {core: {fail}} = require('./wallet');
const PRODUCTS = Object.freeze({coins_100: 100, coins_500: 550, coins_1200: 1400, coins_2500: 3000});
const PACKAGE = 'com.aras.titistar';
const hash = value => createHash('sha256').update(value).digest('hex');
async function google(productId, token, accountToken, config, suppliedClient) {
  const auth = new GoogleAuth({scopes: ['https://www.googleapis.com/auth/androidpublisher']});
  const client = suppliedClient ?? await auth.getClient();
  const url = `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${PACKAGE}/purchases/products/${encodeURIComponent(productId)}/tokens/${encodeURIComponent(token)}`;
  const {data} = await client.request({url, timeout: 15000});
  if (data.purchaseState !== 0 || data.obfuscatedExternalAccountId !== accountToken ||
      (data.quantity ?? 1) !== 1 || (data.purchaseType === 0 && config.allowSandbox !== true))
    fail('failed-precondition', 'الشراء غير مكتمل أو لا يخص هذا الحساب');
  return {id: hash(`android:${PACKAGE}:${token}`), productId, platform: 'android',
    sandbox: data.purchaseType === 0, storeTransactionId: data.orderId ?? null};
}
async function apple(productId, signed, accountToken, config) {
  // DER roots are public Apple PKI certificates configured by the operator.
  const roots = JSON.parse(process.env.APPLE_ROOT_CERTIFICATES_BASE64 || '[]').map(v => Buffer.from(v, 'base64'));
  if (!roots.length || !Number.isSafeInteger(config.appleAppId))
    fail('failed-precondition', 'التحقق من App Store لم يجهز بعد');
  let transaction;
  for (const environment of [Environment.PRODUCTION, ...(config.allowSandbox === true ? [Environment.SANDBOX] : [])]) {
    try {
      const verifier = new SignedDataVerifier(roots, true, environment, PACKAGE, config.appleAppId);
      transaction = await verifier.verifyAndDecodeTransaction(signed);
      break;
    } catch (_) { /* Never trust an unverified decoded payload. */ }
  }
  if (!transaction || transaction.productId !== productId || transaction.appAccountToken !== accountToken ||
      transaction.revocationDate || transaction.quantity !== 1 || transaction.type !== 'Consumable' ||
      !transaction.transactionId || transaction.inAppOwnershipType !== 'PURCHASED')
    fail('failed-precondition', 'فاتورة App Store غير صالحة لهذا الحساب');
  return {id: hash(`ios:${PACKAGE}:${transaction.transactionId}`), productId, platform: 'ios',
    sandbox: transaction.environment === Environment.SANDBOX, storeTransactionId: transaction.transactionId};
}
async function verify(data, accountToken, config) {
  if (!Object.hasOwn(PRODUCTS, data?.productId) || typeof data?.proof !== 'string' ||
      data.proof.length < 10 || data.proof.length > 100000 || typeof accountToken !== 'string')
    fail('invalid-argument', 'بيانات الشراء غير صالحة');
  if (data.platform === 'android') return google(data.productId, data.proof, accountToken, config);
  if (data.platform === 'ios') return apple(data.productId, data.proof, accountToken, config);
  fail('invalid-argument', 'متجر غير مدعوم');
}
module.exports = {verify, PRODUCTS, hash};
Object.defineProperty(module.exports, 'testing', {value: {google}});
