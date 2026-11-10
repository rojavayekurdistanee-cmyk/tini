'use strict';
const {onRequest} = require('firebase-functions/v2/https');
const {onSchedule} = require('firebase-functions/v2/scheduler');
const {getFirestore, Timestamp} = require('firebase-admin/firestore');
const {GoogleAuth} = require('google-auth-library');
const {SignedDataVerifier, Environment} = require('@apple/app-store-server-library');
const {testing: {revoke, reverseRefund}} = require('./purchases');
const {hash} = require('./purchase_verifier');
const PACKAGE = 'com.aras.titistar';
exports.reconcileTiniGoogleRefunds = onSchedule({region: 'europe-west1', schedule: 'every 6 hours', retryCount: 3}, async () => {
  const db = getFirestore(), config = (await db.doc('wallet_config/runtime').get()).data();
  if (!config?.purchasesEnabled || config.migrationInProgress) return;
  const client = await new GoogleAuth({scopes: ['https://www.googleapis.com/auth/androidpublisher']}).getClient();
  const checkpoint = db.doc('wallet_operations/google_refunds');
  const last = (await checkpoint.get()).data()?.checkedUntil?.toMillis?.() ?? 0;
  const end = Date.now() - 60000;
  const start = Math.max(end - 29 * 86400000, last - 86400000);
  let token;
  do {
    const {data} = await client.request({
      url: `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${PACKAGE}/purchases/voidedpurchases`,
      params: {startTime: String(start), endTime: String(end), maxResults: 1000, ...(token ? {token} : {})}, timeout: 20000,
    });
    for (const purchase of data.voidedPurchases ?? []) {
      if (purchase.purchaseToken) await revoke(db, hash(`android:${PACKAGE}:${purchase.purchaseToken}`));
    }
    token = data.tokenPagination?.nextPageToken;
  } while (token);
  await checkpoint.set({checkedUntil: Timestamp.fromMillis(end)});
});
exports.tiniAppleNotifications = onRequest({region: 'europe-west1'}, async (req, res) => {
  if (req.method !== 'POST' || typeof req.body?.signedPayload !== 'string' || req.body.signedPayload.length > 200000)
    return res.status(400).send('Invalid notification');
  const db = getFirestore(), cfg = (await db.doc('wallet_config/runtime').get()).data();
  if (!cfg?.purchasesEnabled || cfg.migrationInProgress) return res.status(503).send('Temporarily paused');
  try {
    const roots = JSON.parse(process.env.APPLE_ROOT_CERTIFICATES_BASE64 || '[]').map(v => Buffer.from(v, 'base64'));
    if (!roots.length || !Number.isSafeInteger(cfg.appleAppId)) return res.status(503).send('Verification not configured');
    let notification, verifier;
    for (const env of [Environment.PRODUCTION, ...(cfg.allowSandbox ? [Environment.SANDBOX] : [])]) {
      try {
        verifier = new SignedDataVerifier(roots, true, env, PACKAGE, cfg.appleAppId);
        notification = await verifier.verifyAndDecodeNotification(req.body.signedPayload);
        break;
      } catch (_) { /* Signature verification is mandatory. */ }
    }
    if (!notification) return res.status(400).send('Invalid signature');
    if (['REFUND', 'REVOKE', 'REFUND_REVERSED'].includes(notification.notificationType)) {
      const transaction = await verifier.verifyAndDecodeTransaction(notification.data.signedTransactionInfo);
      if (!transaction.transactionId || (notification.notificationType !== 'REFUND_REVERSED' && !transaction.revocationDate)) return res.status(400).send('Missing revocation');
      if (!Number.isSafeInteger(notification.signedDate)) return res.status(400).send('Missing signed event date');
      const receiptId = hash(`ios:${PACKAGE}:${transaction.transactionId}`);
      if (notification.notificationType === 'REFUND_REVERSED') await reverseRefund(db, receiptId, notification.signedDate);
      else await revoke(db, receiptId, notification.signedDate);
    }
    return res.status(200).send('OK');
  } catch (_) { return res.status(503).send('Retry notification'); }
});