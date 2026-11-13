# إصلاح إشعارات Tini — مراجعة main بتاريخ 2026-11-13

## المرجع والنطاق

المراجعة والإصلاح مبنيان على `main` عند الالتزام `5b80a7c1fd8f3817c282a3fc5fc2a8cb3c7840f0` فقط. لم تُستخدم فروع R1/R2 أو افتراض وجود ملفات بهذه الأسماء. التغييرات على الفرع المستقل `fix/activity-push-reliability`؛ لا دمج في main ولا نشر إلى Firebase.

## أسباب مثبتة بالكود

| الموضع | النتيجة |
| --- | --- |
| sendActivityNotification يرسل المشاركة والحفظ بلا await | انتهاء الدالة قبل اكتمال الإرسال ممكن؛ لا يثبت سبب كل حالة ميدانية |
| notification+data للإعجاب والتعليق والمتابعة على أندرويد | نظام التشغيل يعرض الإشعار دون renderer الخاص بصور الشخص والفيديو وفحوص الكتم المحلية |
| أنشطة التعليق تكتب وصف الفعل فقط | نص التعليق الحقيقي موجود تحت posts/{postId}/comments/{commentId} ولم يكن يُرفق بالإشعار |
| خلفية Flutter تستخدم DateTime.now().millisecond كمعرف | 1000 قيمة فقط؛ يمكن لإشعار جديد أن يستبدل سابقاً دون علاقة بالفيديو |
| قيم افتراضية title=Tini وbody فارغ | الرسائل الناقصة يمكن عرضها كإشعار فارغ |
| قائمة التوكنات غير منقحة ولا مقسمة | التوكن المكرر يكرر الإرسال، وsendEach يقبل 500 رسالة كحد أقصى |

توليد نشاط المشاركة/الحفظ يستخدم معرفاً ثابتاً لكل شخص/منشور/نوع. تحديث النشاط الموجود لا يشغّل onDocumentCreated من جديد؛ هذا سلوك قائم ولم يتم تغييره. الاختبارات بين فيديوهات مختلفة لا يفسرها ذلك وحده.

## الإصلاح

- أندرويد: data-only بأولوية high لكل أنواع النشاط، ليعرض Flutter صورة الشخص وصورة الفيديو والنص، ويطبق فحوص الخصوصية والكتم وعدم الإزعاج القائمة.
- انتظار جميع دفعات الإرسال، إزالة التوكنات المكررة، تقسيم دفعات 500، ومحاولتان إضافيتان فقط للأخطاء المؤقتة الصريحة. لا يعاد إرسال التوكن الناجح.
- تسجيل نجاح وفشل كل إرسال وإزالة التوكنات التي تؤكد FCM أنها غير صالحة. رفض طلب الإرسال نفسه أو خطأ غير مؤقت يسجل، ولا توجد مهمة إعادة إرسال دائمة جديدة.
- إرفاق النص الحقيقي للتعليق إذا كان متاحاً، والمحافظة على وصف النشاط عند تعذر قراءته. توحيد معرف المنشور بعد lookup للمعرف القديم .mp4 أو حقل postId، كي لا ترفضه فحوص الجمهور بسبب alias فقط.
- إضافة recipient/eventId في البيانات لمنع عرض رسالة حساب آخر وتمييز الحدث عن إعادة تسليمه.
- منع العرض دون body غير فارغ. معرّف عرض ثابت، onlyAlertOnce للتفاعلات، وطابور محلي مع سجل آخر 500 حدث لكل حساب، يسجّل الحدث بعد نجاح العرض فقط.
- إعادة تحميل SharedPreferences في isolate قبل فحوص الكتم، واحترام مفاتيح التفاعلات الخمسة محلياً أيضاً. يبقى فحص خادم التفضيلات الحالي قائماً.
- إبقاء البانرات الداخلية؛ فشل البانر لا يمنع مسار الإشعار الخارجي. مهلة 4 ثوانٍ لكل طلب صورة تسمح بمتابعة عرض النص عند تعطل الشبكة.
- حماية وسائط العرض مرة واحدة، فحوص الجمهور، توجيه الضغط، كتم الغرف والمجموعات، وعدم الإزعاج، ثابت اقتراحات 8888 والوظائف الأخرى لم تُحذف.
- حد بيانات محافظ 3500 بايت: تقصير النصوص بسلامة UTF-8. عند روابط صور ضخمة جداً تُزال البيانات الاختيارية لتجنب رفض FCM للرسالة كلها؛ هذا يعني احتمال عرض النص دون الصور في تلك الحالة.

## حدود iOS المهمة

لا يعامل هذا الإصلاح iOS مثل Android. يحتفظ APNs بتنبيه النظام الحالي للإعجاب والتعليق والمتابعة (داخل apns فقط؛ لا يوجد notification عام يغير مسار أندرويد)، حتى لا تتراجع موثوقية هذه الأنواع عند تعليق Flutter. المشاركة والحفظ يبقيان على مسار البيانات الصامتة الموجود، مع contentAvailable ووضع remote-notification وإعداد Darwin للخلفية وإرفاق الصورة إن منح iOS وقت تنفيذ.

هذا لا يحقق بعد كل المتطلبات على iOS: التنبيه المباشر بالخلفية لا يمر بفحوص DND المحلية أو renderer الخاص بصورة الشخص، ولا يوجد Notification Service Extension في المشروع لعرض الصورتين. إعدادات الأنواع على الخادم تبقى محترمة. الاعتماد الكامل على البيانات الصامتة كان سيخسر موثوقية التنبيهات المباشرة الحالية؛ لذلك لم يُفرض هذا التراجع على iOS. استكمال الصور والفحوص المحلية في جميع حالات iOS يحتاج عملاً أصلياً إضافياً واختبارات توقيع وجهاز حقيقي.

## ما اختُبر فعلياً

- `node --check functions/index.js`: نجح.
- `node --test functions/test/activity_notifications.test.js`: **39 اختباراً ناجحاً** باستخدام mocks لقاعدة البيانات وFCM. يغطي الأنواع الخمسة وأسماءها البديلة، الحقول والصور، إعدادات الخادم الحديثة والقديمة، انتظار المشاركة والحفظ، دفعات 501 توكن، إزالة التكرار، إعادة المحاولات المحدودة، حذف التوكنات غير الصالحة، التعليق، alias المنشور، حدود حجم الرسالة والاستثناءات الموجودة للشات والستوري وزيارة الملف.
- `flutter test --no-pub test/notification_payload_test.dart`: **4 اختبارات ناجحة** لقواعد النص، المستقبِل، مفاتيح الإعدادات وهوية الحدث/الإشعار. هذه اختبارات للقواعد؛ ليست اختبار عرض إشعار فعلي أو اختبار تزامن isolates على الهاتف.
- `dart analyze lib/notification_service.dart lib/notification_payload.dart test/notification_payload_test.dart`: لا أخطاء؛ 11 تحذيراً/ملاحظة موجودة أيضاً في ملف main الأصلي، تمت المقارنة بها. لم تُحذف imports أو تعليقات غير مرتبطة بغرض إسكاتها.
- `flutter build bundle --debug --no-pub`: نجح، بما فيه ترجمة كود التطبيق إلى kernel وحزمة الأصول. استُخدم ملف .env محلي فارغ لأن الملف مطلوب في assets؛ لا يحتوي أسراراً ولا يُرفع.
- صلاحية ios/Runner/Info.plist: نجحت.
- `git diff --check`: نجح.
- `flutter build apk --debug --no-pub`: تعذر إكماله لأن Gradle wrapper لم يتمكن من حل services.gradle.org. لا يُعتبر APK مبنياً أو مجرباً.
- لم تُرسل رسائل FCM حقيقية، ولم يُختبر التطبيق على هاتف أو محاكي أو iPhone، ولم يُنشر أي تعديل إلى الإنتاج.

## اختبار الهاتف قبل اعتماد الإصلاح

1. بناء نسخة Android بالملفين lib/notification_service.dart وlib/notification_payload.dart معاً. تفعيل إذن الإشعارات وقناة titi_star_channel. نشر sendActivityNotification المحددة فقط بعد مراجعة الفرع؛ الرفع إلى GitHub وحده لا يغيّر التطبيق أو Firebase.
2. حسابان على جهازين؛ اختبار إعجاب وتعليق ومتابعة ومشاركة وحفظ لكل من فيديوهين مختلفين، والتطبيق مفتوح، بالخلفية، ثم مغلق إغلاقاً عادياً. تدوين activityId وeventId ووقت كل حدث ونتائج successCount/failureCount من السجلات. نجاح FCM يعني قبولها للإرسال، وليس إثبات ظهورها على الهاتف.
3. التحقق من صورة الشخص والصورة المصغرة بعد توسيع إشعار أندرويد، والنص الفعلي للتعليق، والضغط لفتح المنشور/التعليق/حساب المتابِع.
4. تعطيل كل نوع منفرداً، ثم تفعيل DND داخل الجدول وخارجه وعند عبور منتصف الليل. كتم الخاص والمجموعة، ومعاينة الرسائل، ووسائط العرض مرة واحدة.
5. رسائل ناقصة body يجب ألا تعرض Tini فقط. إعادة تسليم eventId نفسه لا تنشئ تنبيهاً مكرراً؛ حدثان مستقلان يجب أن يبقيا منفصلين. التحقق من تشغيل الهاتف بعد إعادة التشغيل، وتجدد التوكن، وتبديل الحساب وتسجيل الخروج.
6. اختبارات عدم الانحدار: الخاص، المجموعات، البانرات الداخلية، إشعارات اقتراحات/المتابَعين، فحوص الجمهور/المحتوى المقيد، إشعاران متزامنان، وصول بطيء للصور وغياب الشبكة.
7. اختبار Android مع Doze وقيود البطارية وشركات الأجهزة المختلفة. Force Stop يعطل الاستلام حتى إعادة فتح التطبيق؛ iOS قد يؤخر/يسقط الرسائل الصامتة ولا يعيد تشغيل التطبيق بعد إغلاقه قسرياً. هذه حالات لا يضمنها FCM أو كود Flutter.
8. على iOS اختبر التنبيه المباشر للأنواع الثلاثة ومسار المشاركة/الحفظ، ولا تعتمد دعم الصور والكتم المحلي في كل حالات الخلفية قبل استكمال العمل الأصلي الموضح أعلاه.

لا توجد ضمانات exactly-once: السجل المحلي محدود، وSharedPreferences ليست قفلاً ذرياً بين isolates، ومعرّفات Android قد تتصادم نظرياً. المعرف الثابت وonlyAlertOnce يقللان أثر سباق التسليم؛ ما زال اختبار التزامن على الهاتف مطلوباً.

## JavaScript: بلوك كامل قابل للنسخ

يستبدل البلوك التالي دالة sendActivityNotification وحدها، حتى السطر السابق لـ exports.onPostCreated. بقية functions/index.js بقي كما هو.

```javascript
exports.sendActivityNotification = onDocumentCreated({
    region: "europe-west1",
    document: "activities/{activityId}"
}, async (event) => {

    const snap = event.data;
    if (!snap) return null;
    const activity = snap.data();
    const toUid = activity.toUid;
    const fromUid = activity.fromUid;
    const postId = activity.postId ? String(activity.postId) : "";
    let resolvedPostId = postId;
    const commentId = (activity.commentId || "").toString();
    const type = activity.type || "general";

    // [Tini Update] - لا ترسل إشعار خارجي للستوري و زيارة الملف الشخصي + منع تكرار اشعار قد تعرفه
    if (
        type === 'story_new' ||
        type === 'view' ||
        type === 'story_view' ||
        type === 'following_post' ||
        type === 'people_you_may_know_post' ||
        type === 'message' ||
        type === 'chat' ||
        type === 'private_message'
    ) {
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

                senderName =
                    senderData.fullName ||
                    senderData.username ||
                    "مستخدم";

                senderAvatar =
                    senderData.profileImg ||
                    senderData.photoUrl ||
                    senderData.avatarUrl ||
                    senderData.profileImage ||
                    "";
            }
        } catch (e) {
            console.log("sender fetch error", e);
        }

        let finalText =
            String(activity.text || "").trim() || `${senderName} لديه تفاعل جديد`;

        // --- جيب صورة الشات / الفيديو ---
        let postImage = activity.thumbnailUrl || activity.postImage || "";

        if (activity.messageType === 'video' && activity.thumbnailUrl) {
            postImage = activity.thumbnailUrl;
        } else {
            postImage = postImage || activity.mediaUrl || "";
        }

        let postDesc = "";

        // اذا رسالة شات وفيها صورة/فيديو، لا تدور بالبوستات
        let isChatMessage = type === 'message';

        if (postId && !isChatMessage) {
            try {
                let postDoc = await db.collection('posts').doc(postId).get();

                if (!postDoc.exists && postId.endsWith('.mp4')) {
                    const idWithoutExt = postId.replace('.mp4', '');

                    postDoc = await db
                        .collection('posts')
                        .doc(idWithoutExt)
                        .get();
                }

                if (!postDoc.exists) {
                    const q = await db
                        .collection('posts')
                        .where('postId', '==', postId)
                        .limit(1)
                        .get();

                    if (!q.empty) {
                        postDoc = q.docs[0];
                    }
                }

                // fallback للـ videos اذا بدك
                if (!postDoc.exists) {
                    postDoc = await db
                        .collection('videos')
                        .doc(postId)
                        .get();
                }

                if (postDoc.exists) {
                    const postData = postDoc.data();
                    resolvedPostId = postDoc.id;

                    postImage =
                        postData.thumbnailUrl ||
                        postData.postImage ||
                        postData.imageUrl ||
                        postData.mediaUrl ||
                        postData.image ||
                        postImage ||
                        "";

                    postDesc = postData.description || "";

                    console.log(
                        "FOUND POST:",
                        postDoc.id,
                        "thumb:",
                        postImage
                    );
                } else {
                    console.log("POST NOT FOUND FOR:", postId);
                }
            } catch (e) {
                console.log("post fetch error", e);
            }
        }

        // Activity text describes the action; the actual comment is stored separately.
        if ((type === 'comment' || type === 'reply') && commentId && resolvedPostId) {
            try {
                const commentDoc = await db.collection('posts').doc(resolvedPostId)
                    .collection('comments').doc(commentId).get();
                const commentText = commentDoc.exists ? String(commentDoc.data().text || "").trim() : "";
                if (commentText) finalText += `: ${commentText}`;
            } catch (error) {
                console.warn("Activity comment preview unavailable:", error.code || 'unknown');
            }
        }

        // ------------------------------------

        const receiverDoc = await db
            .collection('users')
            .doc(toUid)
            .get();

        if (!receiverDoc.exists) return null;

        const receiverData = receiverDoc.data();

        const prefsDoc = await db
            .doc(`users/${toUid}/notificationSettings/preferences`)
            .get();

        const prefs = prefsDoc.exists ? prefsDoc.data() : null;

        const fcmTokens = receiverData?.fcmTokens || [];

        if (fcmTokens.length === 0) return null;

        const cleanTokens = [...new Set(fcmTokens)].filter(
            t => typeof t === 'string' && t.length > 10
        );

        if (cleanTokens.length === 0) return null;

        // [Tini Update] - ربط زر تسجيلات الإعجاب بقسم التفاعلات
        if (type === 'like') {
            if (
                prefs?.likes === false ||
                receiverData?.notificationSettings?.likes === false
            ) {
                console.log(
                    `Skipped LIKE for ${toUid} - muted from interactions`
                );
                return null;
            }
        }

        // [Tini Update] - ربط زر مرات الإضافة إلى المحفوظات
        if (
            type === 'save' ||
            type === 'bookmark' ||
            type === 'favorite' ||
            type === 'saves'
        ) {
            if (
                prefs?.saves === false ||
                receiverData?.notificationSettings?.saves === false
            ) {
                console.log(
                    `Skipped SAVE for ${toUid} - muted from interactions`
                );
                return null;
            }
        }

        // [Tini Update] - ربط زر التعليقات
        if (type === 'comment') {
            if (
                prefs?.comments === false ||
                receiverData?.notificationSettings?.comments === false
            ) {
                console.log(
                    `Skipped COMMENT for ${toUid} - muted from interactions`
                );
                return null;
            }
        }

        // [Tini Update] - ربط زر متابعون جدد
        if (
            type === 'follow' ||
            type === 'new_follower' ||
            type === 'new_followers'
        ) {
            if (
                prefs?.new_followers === false ||
                receiverData?.notificationSettings?.new_followers === false
            ) {
                console.log(
                    `Skipped FOLLOW for ${toUid} - muted from interactions`
                );
                return null;
            }
        }

        // [Tini Update] - ربط زر منشورات معاد نشرها
        if (
            type === 'repost' ||
            type === 'reposts' ||
            type === 'share'
        ) {
            if (
                prefs?.reposts === false ||
                receiverData?.notificationSettings?.reposts === false
            ) {
                console.log(
                    `Skipped REPOST for ${toUid} - muted from interactions`
                );
                return null;
            }
        }

        // [Tini Update] - ربط زر رسائل خاصة (المهم)
        if (
            type === 'message' ||
            type === 'chat' ||
            type === 'private_message'
        ) {
            if (
                prefs?.private === false ||
                receiverData?.notificationSettings?.private === false
            ) {
                console.log(
                    `Skipped MESSAGE for ${toUid} - muted private messages`
                );
                return null;
            }
        }

        // Android data-only delivery keeps rich images, audience checks and local
        // mute/DND settings in Flutter for every activity type.
        const data = {
            title: senderName,
            body: finalText,
            activityId: event.params.activityId,
            eventId: event.id || event.params.activityId,
            toUid,
            type,
            fromUid: fromUid || "",
            postId: resolvedPostId,
            commentId,
            avatar: senderAvatar || "",
            postImage: postImage || "",
            postDesc: postDesc || ""
        };

        // FCM data values must be strings; leave room below the 4096-byte limit.
        for (const key of Object.keys(data)) data[key] = String(data[key]);
        const trimUtf8 = (value, bytes) => {
            let result = "";
            let length = 0;
            for (const character of value) {
                const size = Buffer.byteLength(character, 'utf8');
                if (length + size > bytes) break;
                result += character;
                length += size;
            }
            return result;
        };
        data.title = trimUtf8(data.title, 200);
        data.body = trimUtf8(data.body, 1200);
        data.postDesc = trimUtf8(data.postDesc, 300);
        for (const key of ['postDesc', 'avatar', 'postImage']) {
            if (Buffer.byteLength(JSON.stringify(data), 'utf8') <= 3500) break;
            data[key] = "";
        }
        if (Buffer.byteLength(JSON.stringify(data), 'utf8') > 3500) {
            console.error("Activity push payload too large:", event.params.activityId);
            return null;
        }

        // Keep the existing iOS OS-visible delivery for likes/comments/follows.
        // Moving these to silent APNs would regress delivery when iOS suspends Flutter.
        const iosSystemAlert = ['like', 'comment', 'follow', 'new_follower', 'new_followers'].includes(type);
        const messages = cleanTokens.map(token => ({
            token,
            data,
            android: { priority: "high" },
            apns: {
                headers: {
                    'apns-push-type': iosSystemAlert ? 'alert' : 'background',
                    'apns-priority': iosSystemAlert ? '10' : '5'
                },
                payload: { aps: iosSystemAlert
                    ? { alert: { title: data.title, body: data.body }, sound: 'default' }
                    : { contentAvailable: true } }
            }
        }));

        const batchResult = { successCount: 0, failureCount: 0, responses: [] };
        const invalidTokens = [];
        const retryableCodes = new Set([
            'messaging/internal-error', 'messaging/server-unavailable',
            'messaging/unknown-error'
        ]);
        // sendEach accepts at most 500 messages. Await every batch, and retry
        // only explicit transient failures, never tokens already accepted by FCM.
        for (let start = 0; start < messages.length; start += 500) {
            let pending = messages.slice(start, start + 500);
            for (let attempt = 0; pending.length && attempt < 3; attempt++) {
                const result = await getMessaging().sendEach(pending);
                const retry = [];
                result.responses.forEach((response, index) => {
                    const code = response.error?.code;
                    if (!response.success && retryableCodes.has(code) && attempt < 2) {
                        retry.push(pending[index]);
                        return;
                    }
                    batchResult.responses.push(response);
                    if (response.success) batchResult.successCount++;
                    else {
                        batchResult.failureCount++;
                        if (code === 'messaging/registration-token-not-registered' ||
                            code === 'messaging/invalid-registration-token') {
                            invalidTokens.push(pending[index].token);
                        }
                    }
                });
                pending = retry;
                if (pending.length) {
                    await new Promise(resolve => setTimeout(resolve, 500 * (attempt + 1)));
                }
            }
        }
        if (invalidTokens.length) {
            try {
                await receiverDoc.ref.update({ fcmTokens: FieldValue.arrayRemove(...invalidTokens) });
            } catch (error) {
                console.warn("Activity push token cleanup failed:", error.code || 'unknown');
            }
        }

        if (batchResult.failureCount > 0) {
            console.warn("Activity push partial/total failure:", {
                activityId: event.params.activityId,
                type,
                successCount: batchResult.successCount,
                failureCount: batchResult.failureCount,

                errors: batchResult.responses
                    .filter(result => !result.success)
                    .map(result => result.error?.code || 'unknown')
            });
        }

        console.log("Activity push completed:", {
            activityId: event.params.activityId,
            type,
            successCount: batchResult.successCount,
            failureCount: batchResult.failureCount
        });

        return {
            success: batchResult.successCount > 0
        };

    } catch (error) {
        console.error("Activity notification error:", error);
        return null;
    }
});
```
