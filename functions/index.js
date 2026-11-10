const { onDocumentDeleted } = require("firebase-functions/v2/firestore");
const { onCall } = require("firebase-functions/v2/https");
const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { onDocumentUpdated } = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const admin = require('firebase-admin');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');
const { getMessaging } = require('firebase-admin/messaging');


// [Tini: IAP] - مكتبات التحقق من الفواتير
const { google } = require("googleapis");
const axios = require("axios");

admin.initializeApp();
const db = getFirestore();

// [Tini: IAP إعدادات] - لازم تغير هذول
const ANDROID_PACKAGE_NAME = "com.aras.titistar";
const APPLE_SHARED_SECRET = "YOUR_APPLE_SHARED_SECRET_HERE";

// جدول المنتجات: كم عملة مقابل كل productId - السيرفر هو المرجع الوحيد
const COIN_PRODUCTS = {
  "coins_100": 100,
  "coins_500": 550, // 500 + 50 بونص
  "coins_1200": 1400, // 1200 + 200 بونص
  "coins_2500": 3000, // 2500 + 500 بونص
};



exports.sendChatPush = onDocumentCreated({
    region: "europe-west1",
    document: "chat_rooms/{roomId}/messages/{messageId}"
}, async (event) => {
    const snap = event.data;
    if (!snap) return null;
    const msg = snap.data();
    const roomId = event.params.roomId;
    const messageId = event.params.messageId;
    if (msg.isDelivered === true) return null;
    try {
        const roomDoc = await db.collection('chat_rooms').doc(roomId).get();
        if (!roomDoc.exists) return null;
        const receiverId = roomDoc.data().participants.find(id => id!== msg.senderId);
        if (!receiverId) return null;
        const receiverDoc = await db.collection('users').doc(receiverId).get();
        if (!receiverDoc.exists) return null;

        // [كتم الخاص] - اذا الغرفة مكتومة لا تبعت
        const roomMutedMap = roomDoc.data().muted || {};
        const prefsDoc = await db.doc(`users/${receiverId}/notificationSettings/preferences`).get();
        const prefs = prefsDoc.exists? prefsDoc.data() : null;
        if (roomMutedMap[receiverId] === true || prefs?.private === false) {
            console.log(`Skipped chat push - muted ${roomId} for ${receiverId}`);
            return null;
        }

        const senderDoc = await db.collection('users').doc(msg.senderId).get();
        const sData = senderDoc.exists? senderDoc.data() : {};
        const senderName = sData.fullName || sData.username || msg.senderName || "مستخدم";
        const senderImg = sData.profileImg || sData.photoUrl || msg.senderImg || msg.senderAvatar || "";

        // [معاينة الرسائل الخاصة + صورة مرسلة كصورة كبيرة]
        const showPreview = prefs?.preview!== false;

        // [Tini Star] حماية وسائط العرض مرة واحدة في إشعارات الخاص
        const isViewOnce = msg.viewOnce === true &&
            (msg.type === 'image' || msg.type === 'video');

        const imageUrl = isViewOnce ? "" : (msg.imageUrl || msg.mediaUrl || msg.fileUrl || msg.image || "");
        const thumbUrl = isViewOnce ? "" : (msg.thumbnailUrl || msg.thumb || msg.thumbnail || "");

        let preview;
        let bigPicture = "";
        if (!showPreview) {
            preview = "لديك رسالة جديدة";
        } else {
            preview = msg.text || "رسالة جديدة";
            if (isViewOnce) {
                preview = msg.type === 'image'
                    ? "📷 صورة لمرة واحدة"
                    : "🎥 فيديو لمرة واحدة";
            } else if (msg.type === 'image') {
                preview = "📷 صورة";
                bigPicture = imageUrl;
            }
            else if (msg.type === 'video') {
                preview = "🎥 فيديو";
                bigPicture = thumbUrl;
            }
            else if (msg.type === 'audio') {
                preview = "🎤 صوت";
            }
        }

        const rawTokens = receiverDoc.data().fcmTokens || [];
        const uniqueTokens = [...new Set(rawTokens)].filter(t => t && t.length > 10);
        if (uniqueTokens.length === 0) return null;

        await getMessaging().sendEach(uniqueTokens.map(token => ({
            token: token,
            data: {
                type: "chat",
                fromUid: msg.senderId || "",
                roomId: roomId,
                messageId: messageId,
                senderId: msg.senderId || "",
                title: senderName,
                body: preview,
                avatar: senderImg,
                senderName: senderName,
                senderImg: senderImg,
                postImage: bigPicture,
                bigPicture: bigPicture,
                imageUrl: bigPicture,
                thumbnailUrl: thumbUrl,
                viewOnce: String(isViewOnce),
            },
            android: { priority: "high" },
            fcmOptions: { analyticsLabel: messageId }
        })));
        return null;
    } catch (e) {
        console.log("sendChatPush error", e);
        return null;
    }
});


// [جديد] اشعارات الجروبات الخارجية + كتم الجروبات
exports.sendGroupChatPush = onDocumentCreated({
    region: "europe-west1",
    document: "group_chats/{groupId}/messages/{messageId}"
}, async (event) => {
    const snap = event.data;
    if (!snap) return null;
    const msg = snap.data();
    const groupId = event.params.groupId;
    const messageId = event.params.messageId;
    if (msg.isDelivered === true) return null;

    try {
        const groupDoc = await db.collection('group_chats').doc(groupId).get();
        if (!groupDoc.exists) return null;
        const groupData = groupDoc.data();
        const members = groupData.members || [];

        for (const uid of members) {
            if (uid === msg.senderId) continue;

            const userDoc = await db.collection('users').doc(uid).get();
            if (!userDoc.exists) continue;
            const userData = userDoc.data();

            // [كتم الجروبات]
            const groupMutedMap = groupData.muted || {};
            const groupPrefsDoc = await db.doc(`users/${uid}/notificationSettings/preferences`).get();
            const groupPrefs = groupPrefsDoc.exists? groupPrefsDoc.data() : null;
            if (groupMutedMap[uid] === true || groupPrefs?.groups === false) {
                continue;
            }

            const rawTokens = userData.fcmTokens || [];
            const uniqueTokens = [...new Set(rawTokens)].filter(t => t && t.length > 10);
            if (uniqueTokens.length === 0) continue;

            await getMessaging().sendEach(uniqueTokens.map(token => ({
                token: token,
                data: {
                    type: "group",
                    fromUid: msg.senderId || "",
                    groupId: groupId,
                    messageId: messageId,
                    senderId: msg.senderId || "",
                    title: groupData.groupName || "مجموعة",
                    body: `${msg.senderName || ''}: ${msg.text || 'صورة'}`,
                    avatar: groupData.groupImage || ""
                },
                android: { priority: "high" },
                fcmOptions: { analyticsLabel: messageId }
            })));
        }
        return null;
    } catch (e) {
        console.log("sendGroupChatPush error", e);
        return null;
    }
});

/**
 * 1. الأرشفة التلقائية عند حذف الحساب (2nd Gen)
 */
exports.archiveDeletedUser = onDocumentDeleted({
    region: "europe-west1",
    document: "users/{userId}"
}, async (event) => {
    const deletedData = event.data.data();
    const userId = event.params.userId;
    console.log('Archiving ID: ' + userId);

    return db.collection('archived_users').doc(userId).set({
     ...deletedData,
        archivedAt: FieldValue.serverTimestamp(),
        status: 'archived_successfully'
    });
});

/**
 * 2. معالجة طلب تصدير البيانات (2nd Gen)
 */
exports.requestUserDataExport = onCall({
    region: "europe-west1"
}, async (request) => {
    if (!request.auth) {
        throw new Error('يجب تسجيل الدخول أولاً');
    }

    const uid = request.auth.uid;
    const userEmail = request.auth.token.email || 'No Email';

    try {
        const userDoc = await db.collection('users').doc(uid).get();
        const userData = userDoc.exists? userDoc.data() : {};

        await db.collection('archived_users').doc(`export_${uid}_${Date.now()}`).set({
            uid: uid,
            fullName: userData.fullName || 'Unknown',
            username: userData.username || 'user',
            email: userEmail,
            requestedAt: FieldValue.serverTimestamp(),
            type: 'manual_export',
            status: 'completed'
        });

        return { success: true, message: 'تم تسجيل طلب تصدير بياناتك بنجاح' };
    } catch (error) {
        console.error('Export Error:', error);
        throw new Error('حدث خطأ أثناء معالجة الطلب');
    }
});

/**
 * 4. [Tini Wallet] - معالجة شراء عملات Tini بأمان (2nd Gen)
 * يتم تشغيلها تلقائياً عند إنشاء طلب شراء جديد في pending_purchases
 * [تم الإصلاح]: إضافة التحقق الحقيقي مع Google Play و Apple
 */
exports.processTiniPurchase = onDocumentCreated({
    region: "europe-west1",
    document: "users/{userId}/pending_purchases/{purchaseId}"
}, async (event) => {
    const snap = event.data;
    if (!snap) return null;

    const purchaseData = snap.data();
    const userId = event.params.userId;
    const purchaseId = event.params.purchaseId;

    console.log(`[Tini Wallet] Processing purchase: ${purchaseId} for user: ${userId}`);

    const userRef = db.collection('users').doc(userId);
    const purchaseRef = userRef.collection('pending_purchases').doc(purchaseId);
    const transactionRef = userRef.collection('transactions').doc();

    try {
        // 1. [أمان] التحقق الحقيقي من الفاتورة مع جوجل/آبل
        const { platform, productId, purchaseToken, receiptData } = purchaseData;

        if (!COIN_PRODUCTS[productId]) {
            throw new Error("Product ID غير معروف أو غير مدعوم");
        }

        let isPaymentValid = false;

        if (platform === "android") {
            if (!purchaseToken) throw new Error("purchaseToken مفقود للأندرويد");
            isPaymentValid = await verifyGooglePlayPurchase(productId, purchaseToken);
        } else if (platform === "ios") {
            if (!receiptData) throw new Error("receiptData مفقود للآيفون");
            isPaymentValid = await verifyApplePurchase(receiptData);
        } else {
            throw new Error("منصة غير مدعومة: " + platform);
        }

        if (!isPaymentValid) {
            await purchaseRef.update({
                status: 'failed',
                error: 'Payment verification failed - الفاتورة مزورة أو مستخدمة',
                processedAt: FieldValue.serverTimestamp()
            });
            console.log(`[Tini Wallet] Payment verification failed for: ${purchaseId}`);
            return null;
        }

        const amountToAdd = COIN_PRODUCTS[productId]; // ناخذ القيمة من السيرفر فقط

        // 2. [أمان]: استخدام Transaction لضمان عدم التكرار
        await db.runTransaction(async (transaction) => {
            const userDoc = await transaction.get(userRef);
            const currentBalance = userDoc.exists? (userDoc.data().tiniBalance || 0) : 0;
            const newBalance = currentBalance + amountToAdd;

            // تحديث الرصيد
            transaction.update(userRef, {
                tiniBalance: newBalance,
                walletUpdatedAt: FieldValue.serverTimestamp()
            });

            // إضافة سجل العملية
            transaction.set(transactionRef, {
                amount: amountToAdd,
                type: 'purchase',
                packageId: productId,
                purchaseId: purchaseId,
                platform: platform,
                createdAt: FieldValue.serverTimestamp(),
                balanceAfter: newBalance
            });

            // تحديث حالة الطلب
            transaction.update(purchaseRef, {
                status: 'completed',
                processedAt: FieldValue.serverTimestamp(),
                balanceAfter: newBalance
            });
        });

        console.log(`[Tini Wallet] Success: Added ${amountToAdd} coins to ${userId}`);
        return { success: true };

    } catch (error) {
        console.error('[Tini Wallet] Error:', error);
        await purchaseRef.update({
            status: 'error',
            error: error.message,
            processedAt: FieldValue.serverTimestamp()
        });
        return null;
    }
});

/**
 * 5. [Tini Wallet] - إنشاء محفظة للمستخدم الجديد
 */
exports.createWallet = onCall({
    region: "europe-west1"
}, async (request) => {
    if (!request.auth) {
        throw new Error('يجب تسجيل الدخول أولاً');
    }

    const uid = request.auth.uid;
    const userRef = db.collection('users').doc(uid);

    try {
        const userDoc = await userRef.get();

        if (userDoc.exists && userDoc.data().tiniBalance!== undefined) {
            return {
                success: true,
                message: 'المحفظة موجودة بالفعل',
                balance: userDoc.data().tiniBalance
            };
        }

        await userRef.set({
            tiniBalance: 0,
            walletCreatedAt: FieldValue.serverTimestamp()
        }, { merge: true });

        console.log(`[Tini Wallet] Wallet created for: ${uid}`);
        return {
            success: true,
            message: 'تم إنشاء المحفظة بنجاح',
            balance: 0
        };

    } catch (error) {
        console.error('[Tini Wallet] Create Error:', error);
        throw new Error('حدث خطأ أثناء إنشاء المحفظة');
    }
});

const nodemailer = require("nodemailer");

const transporter = nodemailer.createTransport({
    service: "gmail",
    auth: {
        user: "arasb5175@gmail.com",
        pass: "mjcc ssga mvmt gnbw"
    }
});

exports.sendMailFromQueue = onDocumentCreated({
    region: "europe-west1",
    document: "mail/{mailId}"
}, async (event) => {
    const snap = event.data;
    if (!snap) return null;
    const mailData = snap.data();

    try {
        await transporter.sendMail({
            from: mailData.from || "arasb5175@gmail.com",
            to: mailData.to,
            subject: mailData.message.subject,
            html: mailData.message.html,
            text: mailData.message.text || ""
        });

        await snap.ref.update({
            delivery: {
                state: "SUCCESS",
                sentAt: FieldValue.serverTimestamp()
            }
        });
        console.log("SUCCESS sent to", mailData.to);

    } catch (error) {
        console.error("ERROR sending mail", error);
        await snap.ref.update({
            delivery: {
                state: "ERROR",
                error: error.message
            }
        });
    }
    return null;
});

exports.sendTwoFactorEmailCode = onCall({
    region: "europe-west1"
}, async (request) => {
    if (!request.auth) throw new Error('يجب تسجيل الدخول أولاً');

    const uid = request.auth.uid;
    const email = request.data.email;
    const code = Math.floor(100000 + Math.random() * 900000).toString();

    await db.collection('users').doc(uid).set({
        twoFactorCode: code,
        twoFactorCodeExpiry: Date.now() + 5 * 60 * 1000
    }, { merge: true });

    await db.collection('mail').add({
        to: email,
        message: {
            subject: "رمز التحقق",
            html: `<h2>رمزك هو: ${code}</h2>`
        }
    });

    return { success: true };
});

exports.sendActivityNotification = onDocumentCreated({
    region: "europe-west1",
    document: "activities/{activityId}"
}, async (event) => {
   
    const snap = event.data;
    if (!snap) return null;
    const activity = snap.data();
    const toUid = activity.toUid;
    const fromUid = activity.fromUid;
    const postId = activity.postId;
    const commentId = (activity.commentId || "").toString();
    const type = activity.type || "general";

// [Tini Update] - لا ترسل إشعار خارجي للستوري و زيارة الملف الشخصي + منع تكرار اشعار قد تعرفه
if (type === 'story_new' || type === 'view' || type === 'story_view' || type === 'following_post' || type === 'people_you_may_know_post' || type === 'message' || type === 'chat' || type === 'private_message') {
  console.log("Skipped external notification for type:", type);
  return null;
}

if (!toUid || toUid === fromUid) return null;

    try {
        let senderAvatar = "";
        let senderName = "مستخدم";
        try {
            const sDoc = await db.collection('users').doc(fromUid).get();
            if (sDoc.exists) {
                const senderData = sDoc.data();
                senderName = senderData.fullName || senderData.username || "مستخدم";
                senderAvatar = senderData.profileImg || senderData.photoUrl || senderData.avatarUrl || senderData.profileImage || "";
            }
        } catch (e) { console.log("sender fetch error", e); }

                let finalText = activity.text || `${senderName} لديه تفاعل جديد`;

                // --- جيب صورة الشات / الفيديو ---
        let postImage = "";
        if (activity.messageType === 'video' && activity.thumbnailUrl) {
          postImage = activity.thumbnailUrl; // اذا فيديو اعرض الصورة المصغرة
        } else {
          postImage = activity.mediaUrl || "";
        }
        let postDesc = "";

        // اذا رسالة شات وفيها صورة/فيديو، لا تدور بالبوستات
        let isChatMessage = type === 'message';

        if (postId &&!isChatMessage) {
            try {
                let postDoc = await db.collection('posts').doc(postId).get();

                if (!postDoc.exists && postId.endsWith('.mp4')) {
                    const idWithoutExt = postId.replace('.mp4','');
                    postDoc = await db.collection('posts').doc(idWithoutExt).get();
                }

                if (!postDoc.exists) {
                    const q = await db.collection('posts').where('postId','==',postId).limit(1).get();
                    if (!q.empty) {
                        postDoc = q.docs[0];
                    }
                }

                // fallback للـ videos اذا بدك
                if (!postDoc.exists) {
                    postDoc = await db.collection('videos').doc(postId).get();
                }

                if (postDoc.exists) {
                    const postData = postDoc.data();
                    postImage = postData.thumbnailUrl || postData.postImage || postData.imageUrl || postData.mediaUrl || postData.image || postImage || "";
                    postDesc = postData.description || "";
                    console.log("FOUND POST:", postDoc.id, "thumb:", postImage);
                } else {
                    console.log("POST NOT FOUND FOR:", postId);
                }
            } catch (e) { console.log("post fetch error", e); }
        }
        // ------------------------------------

        const receiverDoc = await db.collection('users').doc(toUid).get();
        if (!receiverDoc.exists) return null;
        const receiverData = receiverDoc.data();
        const prefsDoc = await db.doc(`users/${toUid}/notificationSettings/preferences`).get();
        const prefs = prefsDoc.exists ? prefsDoc.data() : null;
        const fcmTokens = receiverData?.fcmTokens || [];
        if (fcmTokens.length === 0) return null;
        const cleanTokens = fcmTokens.filter(t => t && t.length > 10);
        if (cleanTokens.length === 0) return null;

                        // [Tini Update] - ربط زر تسجيلات الإعجاب بقسم التفاعلات
        if (type === 'like') {
            if (prefs?.likes === false || receiverData?.notificationSettings?.likes === false) {
                console.log(`Skipped LIKE for ${toUid} - muted from interactions`);
                return null;
            }
        }
        // [Tini Update] - ربط زر مرات الإضافة إلى المحفوظات
        if (type === 'save' || type === 'bookmark' || type === 'favorite' || type === 'saves') {
            if (prefs?.saves === false || receiverData?.notificationSettings?.saves === false) {
                console.log(`Skipped SAVE for ${toUid} - muted from interactions`);
                return null;
            }
        }
        // [Tini Update] - ربط زر التعليقات
        if (type === 'comment') {
            if (prefs?.comments === false || receiverData?.notificationSettings?.comments === false) {
                console.log(`Skipped COMMENT for ${toUid} - muted from interactions`);
                return null;
            }
        }
        // [Tini Update] - ربط زر متابعون جدد
        if (type === 'follow' || type === 'new_follower' || type === 'new_followers') {
            if (prefs?.new_followers === false || receiverData?.notificationSettings?.new_followers === false) {
                console.log(`Skipped FOLLOW for ${toUid} - muted from interactions`);
                return null;
            }
        }
        // [Tini Update] - ربط زر منشورات معاد نشرها
        if (type === 'repost' || type === 'reposts' || type === 'share') {
            if (prefs?.reposts === false || receiverData?.notificationSettings?.reposts === false) {
                console.log(`Skipped REPOST for ${toUid} - muted from interactions`);
                return null;
            }
        }
        // [Tini Update] - ربط زر رسائل خاصة (المهم)
        if (type === 'message' || type === 'chat' || type === 'private_message') {
            if (prefs?.private === false || receiverData?.notificationSettings?.private === false) {
                console.log(`Skipped MESSAGE for ${toUid} - muted private messages`);
                return null;
            }
        }

getMessaging().sendEach(cleanTokens.map(token => ({
            token: token,
            data: {
                title: senderName,
                body: finalText,
                activityId: event.params.activityId,
                type: type,
                fromUid: fromUid || "",
                postId: postId || "",
                commentId: commentId || "",
                avatar: senderAvatar || "",
                postImage: postImage || "",
                postDesc: postDesc || ""
            },
            android: {
                priority: "high"
            }
        })));
        console.log("Data notification sent with avatar:", senderAvatar, "and postImage:", postImage, "commentId:", commentId);
        return { success: true };
    } catch (error) {
        console.error("Activity notification error:", error);
        return null;
    }
});

exports.onPostCreated = onDocumentCreated({
    region: "europe-west1",
    document: "posts/{postId}"
}, async (event) => {
    
    const snap = event.data;
    if (!snap) return null;
    const postData = snap.data();
    if (!postData.videoUrl) {
        console.log("Skip distribution - videoUrl empty");
        return null;
    }
    const postId = event.params.postId;
    const authorId = postData.uid || postData.userId || postData.ownerId || postData.fromUid;
    if (!authorId) return null;

    if (postData.isMysteryBox === true) return null;

    // [إصلاح ثغرة الخصوصية] - أنا فقط و الأصدقاء فقط ما يتوزعو
    const privacy = postData.privacy || 'public';
    if (privacy === 'private' || privacy === 'only_me') return null;

    try {
        // قراءة وحدة بس لكلشي
        const ownerDoc = await db.collection('users').doc(authorId).get();
        const ownerName = ownerDoc.data()?.fullName || ownerDoc.data()?.username || "مستخدم";
        const ownerAvatar = ownerDoc.data()?.profileImg || ownerDoc.data()?.photoUrl || ownerDoc.data()?.avatarUrl || "";

        const followersSnap = await db.collection('users').doc(authorId).collection('followers').limit(100).get();
        const followingSnap = await db.collection('users').doc(authorId).collection('following').limit(50).get();
        const ownerFollowingIds = followingSnap.docs.map(d => d.id);
        const ownerFollowingSet = new Set(ownerFollowingIds);

        // 1. توزيع feed + friendsFeed حسب الخصوصية
        if (!followersSnap.empty) {
            let batch = db.batch();
            let count = 0;
            const privacy = postData.privacy || 'public';
            for (const fDoc of followersSnap.docs) {
                const fid = fDoc.id;
                // الأصدقاء فقط لا يروح لـ feed العادي
                if (privacy !== 'friends') {
                    batch.set(db.collection("users").doc(fid).collection("feed").doc(postId), {
                       ...postData, originalPostId: postId, distributedAt: FieldValue.serverTimestamp()
                    });
                    count++;
                }
                if (ownerFollowingSet.has(fid)) {
                    batch.set(db.collection("users").doc(fid).collection("friendsFeed").doc(postId), {
                       ...postData, originalPostId: postId, distributedAt: FieldValue.serverTimestamp()
                    });
                    count++;
                }
                if (count >= 400) { await batch.commit(); batch = db.batch(); count = 0; }
            }
            if (count > 0) await batch.commit();
        }

        // 2. اشعارات المتابعين - [تصحيح الفاتورة] صار batch بدل واحد واحد
        const followerIds = followersSnap.docs.map(d => d.id).filter(id => id!== authorId);
        if (followerIds.length > 0) {
            const userDocs = await Promise.all(followerIds.map(id => db.collection('users').doc(id).get()));
            const prefsDocs = await Promise.all(followerIds.map(id => db.doc(`users/${id}/notificationSettings/preferences`).get()));
            for (let i = 0; i < userDocs.length; i++) {
                const toUid = followerIds[i];
                const rDoc = userDocs[i];
                if (!rDoc.exists) continue;
                const rData = rDoc.data();
                const prefs = prefsDocs[i].exists ? prefsDocs[i].data() : null;
                if (prefs?.following === false || rData?.notificationSettings?.following === false) continue;
                const tokens = rData?.fcmTokens || [];
                if (tokens.length === 0) continue;
                const cleanTokensFollowing = tokens.filter(t => t && t.length > 10);
                if (cleanTokensFollowing.length === 0) continue;
getMessaging().sendEach(cleanTokensFollowing.map(token => ({
                    token: token,
                    data: {
                        title: ownerName,
                        body: `${ownerName} نشر منشور جديد`,
                        type: "following_post",
                        fromUid: authorId,
                        postId: postId,
                        avatar: ownerAvatar,
                        postImage: postData.thumbnailUrl || postData.mediaUrl || "",
                        postDesc: postData.description || ""
                    },
                    android: { priority: "high" }
                })));
                await db.collection('activities').add({
                    toUid: toUid,
                    fromUid: authorId,
                    type: "following_post",
                    text: `${ownerName} نشر منشور جديد`,
                    postId: postId,
                    seen: false,
                    timestamp: FieldValue.serverTimestamp(),
                });
            }
        }

        // 3. اشعارات قد تعرفه - نفس ميزتك: اقترحنا لك منشور قد يعجبك - [تصحيح الفاتورة] limit
        if (ownerFollowingIds.length >= 2) {
            const sentPYMK = new Set();
            for (const followingId of ownerFollowingIds) {
                const mutualFollowersSnap = await db.collection('users').doc(followingId).collection('followers').limit(20).get();
                for (const mfDoc of mutualFollowersSnap.docs) {
                    const toUid = mfDoc.id;
                    if (toUid === authorId) continue;
                    if (sentPYMK.has(toUid)) continue;
                    if (followersSnap.docs.some(d => d.id === toUid)) continue; // اذا متابعك اصلا تخطى

                    const alreadyFollowing = await db.collection('users').doc(toUid).collection('following').doc(authorId).get();
                    if (alreadyFollowing.exists) continue;

                    const rDoc = await db.collection('users').doc(toUid).get();
                    if (!rDoc.exists) continue;
                    const rData = rDoc.data();
                    const pymkPrefsDoc = await db.doc(`users/${toUid}/notificationSettings/preferences`).get();
                    const pymkPrefs = pymkPrefsDoc.exists ? pymkPrefsDoc.data() : null;
                    if (pymkPrefs?.people_you_may_know === false || rData?.notificationSettings?.people_you_may_know === false) continue;
                    if (!rData?.fcmTokens || rData?.fcmTokens.length === 0) continue;

                    const myFollowingSnap = await db.collection('users').doc(toUid).collection('following').limit(30).get();
                    const myFollowingSet = new Set(myFollowingSnap.docs.map(d => d.id));
                    let mutualCount = 0;
                    ownerFollowingIds.forEach(id => { if (myFollowingSet.has(id)) mutualCount++; });
                    if (mutualCount < 2) continue;

                    sentPYMK.add(toUid);
                    if (sentPYMK.size > 20) break;
                    const tokensPYMK = rData?.fcmTokens || [];
                    const cleanTokensPYMK = tokensPYMK.filter(t => t && t.length > 10);
                    if (cleanTokensPYMK.length === 0) continue;
getMessaging().sendEach(cleanTokensPYMK.map(token => ({
                        token: token,
                        data: {
                            title: ownerName,
                            body: `${ownerName} نشر منشور جديد - لديكم ${mutualCount} اصدقاء مشتركين`,
                            type: "people_you_may_know_post",
                            fromUid: authorId,
                            postId: postId,
                            avatar: ownerAvatar,
                            postImage: postData.thumbnailUrl || postData.mediaUrl || "",
                        },
                        android: { priority: "high" }
                    })));
                    await db.collection('activities').add({
                        toUid: toUid,
                        fromUid: authorId,
                        type: "people_you_may_know_post",
                        text: `${ownerName} نشر منشور جديد - لديكم ${mutualCount} اصدقاء مشتركين`,
                        postId: postId,
                        seen: false,
                        timestamp: FieldValue.serverTimestamp(),
                    });
                }
                if (sentPYMK.size > 20) break;
            }
        }

        return { success: true };
    } catch (e) {
        console.error("onPostCreated merged error:", e);
        return null;
    }
});


exports.onPostUpdated = onDocumentUpdated({
    region: "europe-west1",
    document: "posts/{postId}"
}, async (event) => {
    
    const before = event.data.before.data();
    const after = event.data.after.data();

    // [Tini - Owner Likes Counter] - تعديل إجمالي إعجابات صاحب الفيديو من السيرفر، لا من جهاز المُعجب.
    // مع حماية الحدث من التكرار لأن Firestore قد يعيد إرسال نفس الحدث.
    const previousLikes = Number(before.likesCount || 0);
    const currentLikes = Number(after.likesCount || 0);
    if (Number.isFinite(previousLikes) && Number.isFinite(currentLikes) && previousLikes !== currentLikes) {
        const likesDelta = currentLikes - previousLikes;
        const ownerUid = after.uid || after.userId || after.ownerId || after.fromUid;
        if (ownerUid) {
            const eventRef = db.doc(`posts/${event.params.postId}/likeCountEvents/${event.id}`);
            const postRef = db.collection('posts').doc(event.params.postId);
            const ownerRef = db.collection('users').doc(ownerUid);
            try {
                await db.runTransaction(async (transaction) => {
                    const eventSnap = await transaction.get(eventRef);
                    if (eventSnap.exists) return;
                    const postSnap = await transaction.get(postRef);
                    if (!postSnap.exists) return; // لا ننشئ سجلات جديدة لمنشور حُذف نهائياً.
                    const ownerSnap = await transaction.get(ownerRef);
                    transaction.create(eventRef, {
                        delta: likesDelta,
                        createdAt: FieldValue.serverTimestamp(),
                    });
                    if (ownerSnap.exists) {
                        transaction.update(ownerRef, { likes: FieldValue.increment(likesDelta) });
                    }
                });
            } catch (error) {
                console.error('[Tini Owner Likes Counter] Failed:', error);
                throw error; // المحاولة التلقائية تعيد الحدث دون احتساب مكرر.
            }
        }
    }

    if (before.videoUrl) return null;
    if (!after.videoUrl) return null;
    const postData = after;
    const postId = event.params.postId;
    const authorId = postData.uid || postData.userId || postData.ownerId || postData.fromUid;
    if (!authorId) return null;
    if (postData.isMysteryBox === true) return null;
    // [إصلاح ثغرة الخصوصية]
    const privacyUp = postData.privacy || 'public';
    if (privacyUp === 'private' || privacyUp === 'only_me') return null;
    const followersSnap = await db.collection('users').doc(authorId).collection('followers').limit(100).get();
    const followingSnap = await db.collection('users').doc(authorId).collection('following').limit(50).get();
    const ownerFollowingSet = new Set(followingSnap.docs.map(d => d.id));
    if (!followersSnap.empty) {
        let batch = db.batch();
        let count = 0;
        for (const fDoc of followersSnap.docs) {
            const fid = fDoc.id;
            batch.set(db.collection("users").doc(fid).collection("feed").doc(postId), { ...postData, originalPostId: postId, distributedAt: FieldValue.serverTimestamp() });
            count++;
            if (ownerFollowingSet.has(fid)) {
                batch.set(db.collection("users").doc(fid).collection("friendsFeed").doc(postId), { ...postData, originalPostId: postId, distributedAt: FieldValue.serverTimestamp() });
                count++;
            }
            if (count >= 400) { await batch.commit(); batch = db.batch(); count = 0; }
        }
        if (count > 0) await batch.commit();
    }
    return null;
});


/**
 * 7. [Tini: Feed] - لما حدا يصير يتابع حدا، عبيلو اخر 20 منشور منو - معدل يشتغل مع الاندكس الموجود عندك
 * [تعديل فريندز فيد] - اذا صارت متابعة متبادلة عبي فريندز فيد للطرفين
 */
exports.onFollowCreated = onDocumentCreated({
    region: "europe-west1",
    document: "users/{followerId}/following/{followedId}"
}, async (event) => {
   
    const followerId = event.params.followerId;
    const followedId = event.params.followedId;

    console.log(`[Feed] Backfilling posts from ${followedId} to ${followerId}`);

    try {
        const postsSnap = await db.collection("posts")
        .where("uid", "==", followedId)
        .orderBy("createdAt", "desc")
        .limit(30)
        .get();

        if (postsSnap.empty) {
            console.log('No posts to backfill');
            return null;
        }

        const filteredDocs = postsSnap.docs.filter(d => {
          const p = d.data();
          if (p.isMysteryBox === true) return false;
          const pr = p.privacy || 'public';
          if (pr === 'private' || pr === 'only_me' || pr === 'friends') return false;
          return true;
        }).slice(0,20);

        if (filteredDocs.length === 0) {
            console.log('No posts after filtering mystery box');
            return null;
        }

        const isMutual = await db.collection("users").doc(followedId).collection("following").doc(followerId).get();

        const batch1 = db.batch();
        filteredDocs.forEach(doc => {
            const feedRef = db.collection("users").doc(followerId).collection("feed").doc(doc.id);
            batch1.set(feedRef, {
            ...doc.data(),
                originalPostId: doc.id,
                distributedAt: FieldValue.serverTimestamp(),
            });
            if (isMutual.exists) {
                const ref = db.collection("users").doc(followerId).collection("friendsFeed").doc(doc.id);
                batch1.set(ref, {
                ...doc.data(),
                    originalPostId: doc.id,
                    distributedAt: FieldValue.serverTimestamp(),
                });
            }
        });
        await batch1.commit();
        console.log(`[Feed] Backfilled ${filteredDocs.length} posts`);

        if (isMutual.exists) {
            console.log(`[FriendsFeed] Mutual detected ${followerId} <-> ${followedId}`);
            const otherPostsSnap = await db.collection("posts").where("uid", "==", followerId).orderBy("createdAt", "desc").limit(30).get();
            const otherFiltered = otherPostsSnap.docs.filter(d => d.data().isMysteryBox!== true).slice(0,20);
            const batch2 = db.batch();
            otherFiltered.forEach(doc => {
                const ref = db.collection("users").doc(followedId).collection("friendsFeed").doc(doc.id);
                batch2.set(ref, {
                ...doc.data(),
                    originalPostId: doc.id,
                    distributedAt: FieldValue.serverTimestamp(),
                });
            });
            await batch2.commit();
            console.log(`[FriendsFeed] Backfilled mutual`);
        }

        return { success: true };

    } catch (error) {
        console.error('[Feed] Backfill Error:', error);
        return null;
    }
});

exports.onFollowDeleted = onDocumentDeleted({
    region: "europe-west1",
    document: "users/{followerId}/following/{followedId}"
}, async (event) => {
    const followerId = event.params.followerId;
    const followedId = event.params.followedId;
    
    // [إصلاح أتابعه]: لازم نحذف من feed كمان مو بس friendsFeed
    const feedSnap = await db.collection("users").doc(followerId).collection("feed").where("uid", "==", followedId).limit(500).get();
    const friendsSnap = await db.collection("users").doc(followerId).collection("friendsFeed").where("uid", "==", followedId).limit(500).get();
    
    if (feedSnap.empty && friendsSnap.empty) return null;
    
    const batch = db.batch();
    feedSnap.docs.forEach(d => batch.delete(d.ref));
    friendsSnap.docs.forEach(d => batch.delete(d.ref));
    await batch.commit();
    return null;
});

// --- الفنكشن الجديدة تبع الرائج 1000 ---
exports.updateTrendingFeed = onSchedule({
    
    region: "europe-west1",
    schedule: "every 100 hours",
    memory: "1GiB",
    timeoutSeconds: 300
}, async () => {
    
    
   
   
  console.log('[Trending] Starting update...');

    // [حل الفاتورة] - كنا نقرا كل البوستات، هلا بس اخر 5000 مشان ما نفجر القراءات
    const postsSnapshot = await db.collection('posts')
 .where('isMysteryBox', '==', false)
 .orderBy('createdAt', 'desc')
 .limit(200)
 .get();

  let scoredPosts = [];

  postsSnapshot.forEach(doc => {
    const data = doc.data();
    if (data.privacy === 'private' || data.privacy === 'only_me' || data.privacy === 'friends') return;
    if (data.ownerIsPrivateAccount === true) return;

    const likes = data.likesCount || 0;
    const comments = data.comments || 0;
    const views = typeof data.views === 'number'? data.views : parseInt(data.views) || 0;
    const shares = data.shares || 0;

    const score = likes * 1 + comments * 3 + views * 0.1 + shares * 5;
    const createdAt = data.createdAt? data.createdAt.seconds : 0;

    scoredPosts.push({
   ...data,
      id: doc.id,
      trendingScore: score,
      _createdAt: createdAt,
    });
  });

  // نفس اصلاح الصفر تبعك
  scoredPosts.sort((a, b) => {
    if (a.trendingScore === 0 && b.trendingScore > 0) return 1;
    if (b.trendingScore === 0 && a.trendingScore > 0) return -1;
    if (a.trendingScore === 0 && b.trendingScore === 0) {
      return a._createdAt - b._createdAt;
    }
    if (b.trendingScore!== a.trendingScore) return b.trendingScore - a.trendingScore;
    return a._createdAt - b._createdAt;
  });

  let top1000 = scoredPosts.slice(0, 1000);

  // [حل الشاشة السودا] - اذا الترند فاضي رجع أجدد بوستات بدل ما تترك الصندوق فاضي
  if (top1000.length === 0) {
    console.log('[Trending] No scored posts, fallback to newest 100');
    // استخدمنا نفس الـ snapshot يلي جبناه فوق مشان ما نعمل قراءات زيادة
    const fallback = postsSnapshot.docs.slice(0, 100).map(doc => {
        const data = doc.data();
        return {
         ...data,
          id: doc.id,
          trendingScore: 0,
          _createdAt: data.createdAt?.seconds || 0,
        };
    });
    top1000 = fallback;
  }

  const trendingRef = db.collection('trendingFeed').doc('global').collection('posts');
  const oldDocs = await trendingRef.limit(1000).get();

  const batchSize = 400;
  let batch = db.batch();
  let opCount = 0;

  for (const d of oldDocs.docs) {
    batch.delete(d.ref);
    opCount++;
    if (opCount >= batchSize) { await batch.commit(); batch = db.batch(); opCount = 0; }
  }

  for (const post of top1000) {
    const newDoc = trendingRef.doc(post.id);
    const { _createdAt,...cleanPost } = post;
    batch.set(newDoc, cleanPost);
    opCount++;
    if (opCount >= batchSize) { await batch.commit(); batch = db.batch(); opCount = 0; }
  }

  if (opCount > 0) await batch.commit();

  console.log(`[Trending] Updated with ${top1000.length} posts`);
  return null;
});

/**
 * [Tini: For You] - بناء التوصيات حسب السكور اللي اتفقنا عليه 100 فيديو
 * 1. متابعة +50 | 2. مشاهدة كاملة +40 | 3. لايك +10 | 4. تعليق +20 | 5. مشاركة/Duet +30 | 6. عدم اهتمام -100 وحظر | 7. تنزيل +25 | 8. تخطي سريع -15
 */
// دالة داخلية - نفس منطقك القديم بالحرف
// ... كلشي فوق نفسو ...

exports.refreshForYouScheduled = onSchedule({
    region: "europe-west1",
    schedule: "every 100 hours",
    memory: "1GiB",
    timeoutSeconds: 540
}, async () => {
   
    
     
    const usersSnap = await db.collection('users').where('fcmTokens','!=',null).limit(5).get();

    for (const uDoc of usersSnap.docs) {
        const uData = uDoc.data();
        const myUid = uDoc.id;
        const customPrefsDoc = await db.doc(`users/${myUid}/notificationSettings/preferences`).get();
        const customPrefs = customPrefsDoc.exists? customPrefsDoc.data() : null;
        if (customPrefs?.custom === false || uData?.notificationSettings?.custom === false) continue;

        try {
            const [blockedSnap, blockedBySnap2, hardBlockedSnap, followingSnap, interSnap, postsSnap] = await Promise.all([
                db.collection(`users/${myUid}/blockedChannels`).limit(30).get(),
                db.collection(`users/${myUid}/blockedBy`).limit(100).get(), // [Two-Way]
                db.collection('users').doc(myUid).get(),
                db.collection(`users/${myUid}/following`).limit(50).get(),
                db.collection(`userInteractions`).where('userId','==',myUid).limit(20).get(),
                db.collection('posts').where('isMysteryBox','==',false).orderBy('createdAt','desc').limit(30).get()
            ]);

            const blockedIds = new Set(blockedSnap.docs.map(d=>d.id));
            const blockedByIds2 = new Set(blockedBySnap2.docs.map(d=>d.id));
            // [HARD BLOCK - مركزي]
            const hardBlockedData = hardBlockedSnap.data() || {};
            const hardBlockedList = hardBlockedData.blockedUsers || hardBlockedData.blocked || [];
            const hardBlockedIds = new Set(hardBlockedList);
            const followingIds = new Set(followingSnap.docs.map(d=>d.id));
            const interMap = {};
            interSnap.docs.forEach(d => interMap[d.data().postId] = d.data());

            let scored = [];
            for (const doc of postsSnap.docs) {
                const data = doc.data();
                if (blockedIds.has(data.uid)) continue;
                if (hardBlockedIds.has(data.uid)) continue;
                if (blockedByIds2.has(data.uid)) continue; // [Two-Way]
                if (data.privacy === 'private' || data.privacy === 'only_me' || data.privacy === 'friends') continue;
                if (data.uid === myUid) continue;
                let score = 0;
                if (followingIds.has(data.uid)) score += 50;
                const inter = interMap[doc.id];
                if (inter) {
                    if (inter.watchFull) score += 40;
                    if (inter.liked) score += 10;
                    if (inter.commented) score += 20;
                    if (inter.shared) score += 30;
                } else {
                    score += Math.random() * 5;
                }
                scored.push({...data, id: doc.id, score});
            }
            scored.sort((a,b) => b.score - a.score);
            const top = scored[0];
            if (!top) continue;

            // 1- خارجي
            const tokensCustom = uData?.fcmTokens || [];
            const cleanTokensCustom = tokensCustom.filter(t => t && t.length > 10);
            if (cleanTokensCustom.length === 0) continue;
getMessaging().sendEach(cleanTokensCustom.map(token => ({
                token: token,
                data: {
                    title: "اقترحنا لك",
                    body: "منشور قد يعجبك بناء على تفاعلاتك",
                    type: "custom_suggestion",
                    postId: top.id,
                    fromUid: top.uid || "",
                    avatar: "",
                    postImage: top.thumbnailUrl || top.mediaUrl || "",
                    postDesc: top.description || ""
                },
                android: { priority: "high" }
            })));

            // 2- داخلي بصفحه الاشعارات
            await db.collection('activities').add({
                toUid: myUid,
                fromUid: top.uid || "system",
                type: "custom_suggestion",
                text: "اقترحنا لك منشور قد يعجبك",
                postId: top.id,
                mediaUrl: top.thumbnailUrl || top.mediaUrl || "",
                seen: false,
                timestamp: FieldValue.serverTimestamp(),
            });

        } catch(e) {}
    }
    return null;
});

exports.getForYouOnScroll = onCall({ region: "europe-west1" }, async (request) => {
    
    if (!request.auth) throw new Error('يجب تسجيل الدخول');
    const myUid = request.auth.uid;
    const seenIds = request.data?.seenIds || [];
    const [blockedSnap, blockedBySnap, hardBlockedSnap, followingSnap, interSnap, postsSnap, hashtagSnap] = await Promise.all([
        db.collection(`users/${myUid}/blockedChannels`).limit(30).get(),
        db.collection(`users/${myUid}/blockedBy`).limit(100).get(), // [Two-Way] مين حاظرني
        db.collection('users').doc(myUid).get(),
        db.collection(`users/${myUid}/following`).limit(50).get(),
        db.collection(`userInteractions`).where('userId','==',myUid).limit(100).get(),
        db.collection('posts').where('isMysteryBox','==',false).orderBy('createdAt','desc').limit(100).get(),
        db.collection(`users/${myUid}/hashtagInterests`).orderBy('count','desc').limit(10).get()
    ]);
    const blockedIds = new Set(blockedSnap.docs.map(d=>d.id));
    const blockedByIds = new Set(blockedBySnap.docs.map(d=>d.id)); // [Two-Way]
    // [HARD BLOCK - مركزي]
    const hardData = hardBlockedSnap.data() || {};
    const hardList = hardData.blockedUsers || hardData.blocked || [];
    const hardBlockedIds = new Set(hardList);
    const followingIds = new Set(followingSnap.docs.map(d=>d.id));
    const interMap = {};
    interSnap.docs.forEach(d => interMap[d.data().postId] = d.data());
    const hashtagMap = {}; // <-- جديد
    hashtagSnap.docs.forEach(doc => { hashtagMap[doc.id] = doc.data().count || 0; }); // <-- جديد
    const seenSet = new Set(seenIds);
    let scored = [];
    for (const doc of postsSnap.docs) {
        if (seenSet.has(doc.id)) continue;
        const data = doc.data();
        if (blockedIds.has(data.uid)) continue;
        if (hardBlockedIds.has(data.uid)) continue;
        if (blockedByIds.has(data.uid)) continue; // [Two-Way] اذا هو حاظرني لا تبعتلي فيديوهاته ولا تبعت فيديوهاتي لعندو
        if (data.privacy === 'private' || data.privacy === 'only_me' || data.privacy === 'friends') continue;
        if (data.ownerIsPrivateAccount === true) continue;
        if (data.isMysteryBox === true) continue;
        if (data.uid === myUid) continue;
        let score = 0;
        if (followingIds.has(data.uid)) score += 50;
        // --- اضافة جديدة ---
        if (data.hashtags && Array.isArray(data.hashtags)) {
            for (const h of data.hashtags) {
                const cleanH = h.toString().toLowerCase().replace('#','').trim();
                if (hashtagMap[cleanH]) score += hashtagMap[cleanH] * 10;
            }
        }
        // --- نهاية الاضافة ---
        const inter = interMap[doc.id];
        if (inter) {
            if (inter.notInterested) continue;
            if (inter.watchFull) score += 40;
            if (inter.quickSkip) score -= 20;
            if (inter.superSkip) score -= 15;
            if (inter.liked) score += 10;
            if (inter.commented) score += 20;
            if (inter.shared || inter.duet) score += 30;
            if (inter.downloaded) score += 25;
        } else {
            score += Math.random() * 5;
        }
        scored.push({...data, id: doc.id, score });
    }
    scored.sort((a,b) => b.score - a.score);
    return { posts: scored.slice(0, 20).map(p => p.id) };
});

/**
 * [Tini: For You] - تسجيل اي تفاعل + بلوك القناة - حظر شامل توصيات + رائج
 */
exports.logInteraction = onCall({ region: "europe-west1" }, async (request) => {
    
    if (!request.auth) throw new Error('يجب تسجيل الدخول');
    const myUid = request.auth.uid;
    const { postId, type, ownerId } = request.data;

    if (type === 'notInterested') {
        if (myUid === ownerId) return { success: true };

        const followingDoc = await db.doc(`users/${myUid}/following/${ownerId}`).get();
        if (followingDoc.exists) {
            // صديق - ما نحظر، بس نتجاهل
            return { success: true, blocked: false, reason: 'friend' };
        }

        // حظر شامل
        await db.collection(`users/${myUid}/blockedChannels`).doc(ownerId).set({
            blockedAt: FieldValue.serverTimestamp(),
            ownerId
        });

        // [تصليح الرجوع] امسح كل فيديوهاتو من الفيد تبعك انت بس
        const feedSnap = await db.collection(`users/${myUid}/feed`).where('uid','==',ownerId).limit(100).get();
        const friendsSnap = await db.collection(`users/${myUid}/friendsFeed`).where('uid','==',ownerId).limit(100).get();
        const batch = db.batch();
        feedSnap.docs.forEach(d => batch.delete(d.ref));
        friendsSnap.docs.forEach(d => batch.delete(d.ref));
        await batch.commit();

        // 👇 هاد يلي كان ناقص - مشان ما يرجع يطلعلك ابدا بالـ For You
        await db.collection('userInteractions').doc(`${myUid}_${postId}`).set({
            userId: myUid,
            postId,
            notInterested: true,
            updatedAt: FieldValue.serverTimestamp()
        }, { merge: true });

        return { success: true, blocked: true };
    }

    const docId = `${myUid}_${postId}`;
    await db.collection('userInteractions').doc(docId).set({
        userId: myUid,
        postId,
        [type]: true,
        updatedAt: FieldValue.serverTimestamp()
    }, { merge: true });

    return { success: true };
});

/**
 * [Tini: IAP Helper] التحقق من فاتورة Google Play
 * TEMP: معطل مؤقتاً - التطبيق لسه مش على Play Store
 * قبل النشر: شيل الـ return true وفعل الكود المعلق + ارفع service-account.json
 */
async function verifyGooglePlayPurchase(productId, purchaseToken) {
  console.log("TEMP: Google Play verification DISABLED - returning true");
  return true; // هسا أي فاتورة رح تتقبل. احذف هذا السطر قبل النشر!

  /*
  // الكود الحقيقي - فعّله قبل نشر التطبيق
  const auth = new google.auth.GoogleAuth({
    keyFile: "service-account.json",
    scopes: ["https://www.googleapis.com/auth/androidpublisher"],
  });

  const androidpublisher = google.androidpublisher({version: "v3", auth});

  try {
    const res = await androidpublisher.purchases.products.get({
      packageName: ANDROID_PACKAGE_NAME,
      productId: productId,
      token: purchaseToken,
    });
    return res.data.purchaseState === 0;
  } catch (e) {
    console.error("Google Play Verify Error:", e.message);
    return false;
  }
  */
}

/**
 * [Tini: IAP Helper] التحقق من فاتورة Apple App Store
 * TEMP: معطل مؤقتاً - التطبيق لسه مش على App Store
 * قبل النشر: شيل الـ return true وفعل الكود المعلق + حط APPLE_SHARED_SECRET
 */
async function verifyApplePurchase(receiptData) {
  console.log("TEMP: Apple verification DISABLED - returning true");
  return true; // هسا أي فاتورة رح تتقبل. احذف هذا السطر قبل النشر!

  /*
  // الكود الحقيقي - فعّله قبل نشر التطبيق
  const verifyUrl = "https://buy.itunes.apple.com/verifyReceipt"; // للإنتاج
  // const verifyUrl = "https://sandbox.itunes.apple.com/verifyReceipt"; // للتجربة

  try {
    const res = await axios.post(verifyUrl, {
      "receipt-data": receiptData,
      "password": APPLE_SHARED_SECRET,
      "exclude-old-transactions": true,
    });
    return res.data.status === 0;
  } catch (e) {
    console.error("Apple Verify Error:", e.message);
    return false;
  }
  */
}
/**
 * [Tini: Full Purge] - حذف شامل من كل مكان
 */

exports.onPostDeletedCleanup = onDocumentDeleted({
    region: "europe-west1",
    document: "posts/{postId}"
}, async (event) => {
    const postId = event.params.postId;
    console.log(`[Full Purge] ${postId}`);

    try {
        const usersSnap = await db.collection('users').get();
        let batch = db.batch();
        let count = 0;
        const cols = ['feed', 'friendsFeed', 'favorites', 'sharedPosts', 'likedPosts'];

        for (const u of usersSnap.docs) {
            for (const col of cols) {
                batch.delete(db.doc(`users/${u.id}/${col}/${postId}`));
                count++;
                if (count >= 400) {
                    await batch.commit();
                    batch = db.batch();
                    count = 0;
                }
            }
        }

        batch.delete(db.doc(`trendingFeed/global/posts/${postId}`));
        count++;

        await batch.commit();

        // [Tini - Owner Reactions Overlay] - حذف فهرس الإعجابات وسجلات منع تكرار العدّاد.
        // Firestore لا يمسح المجموعات الفرعية تلقائياً عند حذف مستند الفيديو.
        const postRef = db.collection('posts').doc(postId);
        for (const subcollection of ['likes', 'likeCountEvents']) {
            while (true) {
                const page = await postRef.collection(subcollection).limit(350).get();
                if (page.empty) break;
                const cleanupBatch = db.batch();
                for (const document of page.docs) cleanupBatch.delete(document.ref);
                await cleanupBatch.commit();
                if (page.size < 350) break;
            }
        }

        console.log(`[Full Purge] Done ${postId}`);
    } catch (e) {
        console.error("Purge Error", e);
    }
    return null;
});

/**
 * [Tini: المحذوفات] - حذف نهائي تلقائي بعد 30 يوم من Firestore + R2
 */
const { S3Client, DeleteObjectCommand } = require("@aws-sdk/client-s3");

const s3 = new S3Client({
  region: "auto",
  endpoint: `https://${process.env.R2_ACCOUNT_ID}.r2.cloudflarestorage.com`,
  credentials: {
    accessKeyId: process.env.R2_ACCESS_KEY_ID,
    secretAccessKey: process.env.R2_SECRET_ACCESS_KEY,
  },
});

exports.cleanupDeletedPosts = onSchedule({
    region: "europe-west1",
    schedule: "every 24 hours",
    timeoutSeconds: 540,
    memory: "512MiB"
}, async () => {
    console.log('[Trash] Starting cleanup...');
    const now = new Date();

    const snap = await db.collection('posts')
      .where('isDeleted', '==', true)
      .where('expireAt', '<=', now)
      .limit(200)
      .get();

    if (snap.empty) {
        console.log('[Trash] Nothing to delete');
        return null;
    }

    let batch = db.batch();
    let count = 0;

    for (const doc of snap.docs) {
        const data = doc.data();
        
        // 1- حذف الفيديو من R2
        if (data.videoUrl) {
            try {
                const url = new URL(data.videoUrl);
                const key = decodeURIComponent(url.pathname.substring(1));
                await s3.send(new DeleteObjectCommand({
                    Bucket: process.env.R2_BUCKET_NAME,
                    Key: key,
                }));
                console.log(`[Trash] Deleted video from R2: ${key}`);
            } catch (e) {
                console.log(`[Trash] R2 video delete failed for ${doc.id}:`, e.message);
            }
        }

        // 1.1 - حذف الصورة المصغرة من R2
        if (data.thumbnailUrl) {
            try {
                const url = new URL(data.thumbnailUrl);
                const thumbKey = decodeURIComponent(url.pathname.substring(1));
                await s3.send(new DeleteObjectCommand({
                    Bucket: process.env.R2_BUCKET_NAME,
                    Key: thumbKey,
                }));
                console.log(`[Trash] Deleted thumb from R2: ${thumbKey}`);
            } catch (e) {
                console.log(`[Trash] R2 thumb delete failed for ${doc.id}:`, e.message);
            }
        }

        // 2- حذف الدوكيمنت من Firestore
        batch.delete(doc.ref);
        count++;
        if (count >= 400) {
            await batch.commit();
            batch = db.batch();
            count = 0;
        }
    }

    if (count > 0) await batch.commit();

    console.log(`[Trash] Deleted ${snap.size} expired posts from Firestore + R2`);
    return null;
});

/**
 * [عرض مرة واحدة - الجروبات] حذف تلقائي بعد 10 أيام
 * أي صورة/فيديو "مرة واحدة" ما انحذفت (بعض الأعضاء ما فتحوها) بتنحذف من R2 بعد 10 أيام.
 * بتفحص بس الرسائل اللي عمرها بين 10 و 40 يوم عشان الفحص يضل خفيف.
 */
exports.cleanupExpiredViewOnce = onSchedule({
    region: "europe-west1",
    schedule: "every 24 hours",
    timeoutSeconds: 540,
    memory: "512MiB"
}, async () => {
    const DAY = 24 * 60 * 60 * 1000;
    const now = Date.now();
    const cutoff = new Date(now - 10 * DAY);
    const oldest = new Date(now - 40 * DAY);

    const snap = await db.collectionGroup('messages')
        .where('viewOnce', '==', true)
        .where('timestamp', '>=', oldest)
        .where('timestamp', '<=', cutoff)
        .limit(500)
        .get();

    if (snap.empty) {
        console.log('[ViewOnce] Nothing expired');
        return null;
    }

    let deleted = 0;
    for (const doc of snap.docs) {
        const data = doc.data();
        if (!data.mediaUrl) continue; // انحذفت قبل

        try {
            const url = new URL(data.mediaUrl);
            const key = decodeURIComponent(url.pathname.substring(1));
            await s3.send(new DeleteObjectCommand({
                Bucket: process.env.R2_BUCKET_NAME,
                Key: key,
            }));
            await doc.ref.update({ mediaUrl: null, mediaDeleted: true });
            deleted++;
        } catch (e) {
            console.log(`[ViewOnce] Expire failed for ${doc.ref.path}:`, e.message);
        }
    }

    console.log(`[ViewOnce] Expired ${deleted} view-once media`);
    return null;
});
for (let k in exports) delete exports[k];