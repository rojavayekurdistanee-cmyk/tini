# ربط محفظة Tini بالعرش والشراء

## ما نُفّذ

مصدر الرصيد الوحيد بعد الانتقال هو `users/{uid}`:

| الحقل | المعنى |
|---|---|
| `walletVersion: 2` | المحفظة انتقلت إلى المسار الجديد |
| `tiniBalance` | العملات المتاحة للإنفاق |
| `throneReservedPoints` | حجز العرش، منفصل عن المتاح |
| `boxReservedPoints` | مجموع حجوزات الصناديق |
| `walletDebt` | مبلغ تسوية مدفوعات مسترجعة استُخدمت عملاتها |
| `purchaseAccountToken` | UUID يولده الخادم لربط فاتورة المتجر بالحساب |

المزايدة تحجز من المتاح. رفع مزايدتك يحجز الفرق فقط. خسارة الصدارة تعيد الحجز. التتويج يسوّي المحجوز دون خصم المتاح مرة ثانية. الصندوق يحجز، ثم يسوّي الحجز ويدفع للبائع داخل المعاملة نفسها، أو يعيد المال عند الإلغاء/انتهاء عشر دقائق. لا يوجد تحويل للعملات عبر كود Flutter.

إعادة الحجز وعائد البيع والعملات الجديدة تغطي الدين أولاً إن وُجد. الدين يمنع إنفاقاً جديداً. التسوية لا تعيد ضبط ملك أو تاريخ تتويج سابق. رصيد الاختبار واضح في السجل ولا يُسمّى شراءً موثقاً.

مدد العرش لم تتغير: المزاد 24 ساعة، الحكم العادي 24 ساعة، والتتويج الفوري عند 10,000 لمدة سبعة أيام. الشارات والتفاعلات والقاعة وواجهات الصناديق وجمهورها باقية.

## الملفات

| الملف | دوره |
|---|---|
| `lib/wallet_provider.dart` | متابعة الحساب والرصيد؛ الشراء وربط الحساب؛ إرسال الإثبات؛ تأكيد المتجر بعد التسليم فقط؛ إعادة المحاولة |
| `lib/wallet_screen.dart` | المتاح والمحجوز والتسوية؛ أسعار المتجر الحقيقية؛ رسائل الشراء؛ أنواع سجل واضحة |
| `lib/main.dart` | بدء متابعة نتائج الشراء عند تشغيل التطبيق حتى لو لم تُفتح المحفظة |
| `lib/crown_provider.dart` | قراءة الرصيد نفسه الذي تعرضه المحفظة |
| `lib/box_provider.dart` | استدعاء الحجز/الشراء/الإلغاء الخادمي، مع حفظ معرّف الطلب لإعادة المحاولة |
| `functions/throne-v2/wallet.js` | التهيئة الآمنة والتحقق من الأرصدة والهوية والسجل |
| `functions/throne-v2/purchase_verifier.js` | Google Play Developer API وApple SignedDataVerifier، وربط الفاتورة بالحساب والمنتج والكمية |
| `functions/throne-v2/purchases.js` | تسليم الفاتورة مرة واحدة عالمياً؛ التسوية والعكس |
| `functions/throne-v2/refunds.js` | متابعة Google voided purchases؛ إشعارات Apple الموقعة REFUND/REVOKE/REFUND_REVERSED |
| `functions/throne-v2/box_wallet.js` | معاملات الصناديق؛ استرجاع الحجوزات المنتهية؛ دفع البائع ومنح الشارة مرة واحدة |
| `functions/throne-v2/throne.js` | الحجز والاسترجاع والتتويج من المحفظة الموحدة؛ استمرار معالجة الحالة القديمة إلى حين الانتقال |
| `functions/throne-v2/admin.js` | منح اختبار للمحفظة الجديدة فقط، ومنعه عند تمكين الشراء الحقيقي؛ تفعيل/إيقاف المزايدة |
| `functions/throne-v2/migrate_wallets.js` | تقرير للقراءة فقط؛ انتقال بمراجعة صريحة مع حفظ الحالة السابقة ومنع تكراره |
| `functions/throne-v2/index.js` | تصدير الوظائف الجديدة من codebase العرش |
| `functions/index.js` | إغلاق مسار الإضافة القديم ومعرّفات التحقق الوهمية؛ إبقاء سطر حذف exports كما وضعه المالك |
| `firestore.rules` | حماية حقول المال والشارات والحجز والسجل والفواتير من تعديل العميل؛ استمرار تعديل الملف والمنشورات العادية |
| `pubspec.yaml`, `pubspec.lock` | اعتماد Android المباشر للاستهلاك بعد التسليم، دون تحديث Flutter أو بقية الحزم |
| `functions/throne-v2/package.json`, `package-lock.json` | مكتبات التحقق الرسمية واعتمادات اختبارات المحاكي المثبتة |
| `functions/throne-v2/test/*.test.js` | اختبارات المال والتزامن والقواعد والانتقال |
| `.gitignore` | استبعاد ملفات إعدادات الخادم المحلية وتقارير الحسابات |

لم يُغيّر `firebase.json` أو بقية وظائف الملف الكبير، ولم يُحذف سطر `for (let k in exports) delete exports[k];`.
عند تجهيز نسخة `functions/index.js` للنشر استُبدلت كلمة مرور البريد المضمّنة بقراءة `process.env.TINI_MAIL_APP_PASSWORD` كي لا تُعاد مشاركة سر في الملف. إذا قررت تشغيل وظيفة البريد لاحقاً، يلزم توفير هذا المتغير في إعداد الخادم. لم نفعّل البريد أو ننشره.

## شرط المتاجر قبل أي دفع حقيقي

يمكن إعداد واختبار الشراء قبل الإطلاق العام، باستخدام مسار اختبار المتجر. لا يكفي `flutter run` وحده لاعتبار الدفع الحقيقي مجرّباً.

1. أنشئ المنتجات المستهلكة بالمعرّفات نفسها في المتجرين:
   `coins_100=100`، `coins_500=550`، `coins_1200=1400`، `coins_2500=3000`.
   العملات تحددها خريطة الخادم، والسعر تعرضه بيانات المتجر فقط.
2. Google Play: تطبيق `com.aras.titistar`، إصدار ضمن مسار اختبار، وحساب مختبر ترخيص. فعّل Android Publisher API وأعط حساب الخدمة الذي يشغّل الوظائف صلاحيات التطبيق اللازمة في Play Console لقراءة الشراء والطلبات المالية المسترجعة. ربط حساب الفوترة وحده لا يعطي هذه الصلاحيات. لا تضع مفتاح خدمة داخل التطبيق أو المستودع.
3. Apple: Bundle ID نفسه، منتجات App Store Connect، حساب Sandbox/TestFlight. المسار الجديد يقبل إثبات StoreKit 2 الموقع JWS؛ الفواتير القديمة غير المربوطة بـappAccountToken لا تُنقل تلقائياً. إصدار StoreKit الموجود يدعم StoreKit 2؛ لا تُعطّله لاستعمال المسار القديم.
4. اضبط رقم Apple العددي `appleAppId` داخل `wallet_config/runtime`، وجذور Apple الرسمية DER داخل متغير الخادم `APPLE_ROOT_CERTIFICATES_BASE64` بصيغة JSON array من شهادات base64. هذه شهادات عامة من Apple PKI، وليست شهادة ذاتية أو مفتاحاً خاصاً. التحقق يشمل سلسلة التوقيع وبيئة المتجر والتطبيق وفحص الشهادات عبر الشبكة.
5. اضبط عنوان `tiniAppleNotifications` كعنوان App Store Server Notifications V2 للإنتاج وSandbox، وتحقق من اختبار وصول الإشعار من App Store Connect. وقّع التطبيق واضبط App Check للإصدار النهائي؛ رمز debug للتطوير فقط.
6. بعد تهيئة المتجر والانتقال فقط، اضبط من الخادم `purchasesEnabled: true`. للاختبار اضبط `allowSandbox: true`، وللإنتاج `allowSandbox: false`. هذه الحقول لا يستطيع التطبيق تعديلها. استعمل مشروع اختبار منفصل لعمليات Sandbox إذا أردت فصلها عن الإنتاج.
7. لا تنقل المنح التجريبية إلى إطلاق مدفوع دون مراجعة الأرصدة. أداة المنح الجديدة ترفض العمل أثناء تمكين الشراء.

التحقق يُلزم فاتورة مكتملة لكمية واحدة وبمنتج معروف وبمعرّف الحساب الذي أنشأه الخادم. Google يستخدم token، وApple يستخدم transactionId لمنع تكرار عالمي حتى بين مستخدمين. فشل الشبكة يترك العملية غير منتهية في المتجر لإعادة المحاولة؛ لا تكتمل مبكراً بعد مجرد كتابة طلب إلى Firestore. العملات المستهلكة المنتهية لا يمكن استعادتها كشراء جديد؛ الزر يتابع العمليات غير المكتملة فقط.

## نشر وانتقال على المشروع — لم يُنفّذا تلقائياً

نفّذ هذه الخطوات فقط عند استعدادك للانتقال. لا تنفذ نشر `functions` العام: سطر exports في الملف الكبير مقصود ويظل قرار نشره لك.

1. احتفظ بنسخة احتياطية من Firestore وبنسخة التطبيق السابقة. راجع الوظائف المنشورة فعلياً؛ تأكد أن `processTiniPurchase` و`createWallet` القديمتين غير منشورتين/أوقفهما إن كانتا موجودتين. تعديل الملف مع بقاء سطر حذف exports لا يحدث دالة قديمة منشورة تلقائياً. لا يجوز بقاء معالج قديم يضيف العملات إلى جانب الجديد.
2. أوقف استعمال العملاء القدامى أثناء الانتقال. سوِّ أي حجوزات صناديق قديمة بمراجعة خادمية قبل المتابعة؛ الأداة ترفض تخمين ما خُصم بالنسخة القديمة أو رد مبالغ اعتماداً على حقول عميل غير موثوقة.
3. في `C:\Work\tini` ثبّت اعتمادات المصدر: `npm ci --prefix functions/throne-v2`. يمكن استخدام `--omit=dev` لنسخة النشر.
4. انشر codebase المحدد: `firebase deploy --only functions:throne-v2 --project=titi-star0`.
   الشراء الجديد معطل افتراضياً إذا لم يوجد إعداد موثق للمحفظة. هذا الإصدار يستطيع إنهاء الحالة القديمة من مصدرها القديم قبل بدء قفل الانتقال.
5. انشر القواعد المحددة: `firebase deploy --only firestore:rules --project=titi-star0`.
   لا تنشر ملف فهارس جزئياً بدلاً من فهارس المشروع الكاملة.
6. تقرير أولي للقراءة فقط:
   `node functions/throne-v2/migrate_wallets.js inspect --project=titi-star0 --out=wallet-migration-before.json`
7. ابدأ قفل الانتقال (يوقف المزايدة والكتابة المالية وإنشاء ملفات حسابات جديدة مؤقتاً، دون تغيير أوقات الحكم):
   `node functions/throne-v2/migrate_wallets.js begin --project=titi-star0 --run-id=wallet-v2-001`
8. أنشئ التقرير النهائي تحت القفل:
   `node functions/throne-v2/migrate_wallets.js inspect --project=titi-star0 --out=wallet-migration-reviewed.json`
9. راجع كل حساب في التقرير. حدد `available` كرصيد متاح نهائي صريح، و`classification` إما `test` أو `reviewed_opening`، و`reason` يشرح مصدر القرار. لا تجمع `oldWalletBalance` و`oldThroneWallet.availablePoints` تلقائياً. احتفظ بـ`expectedDigest` وبقية معلومات التقرير كما هي. `available: 0` اختيار صالح لحذف الرصيد التجريبي المتاح؛ الاحتفاظ به اختيار يجب توثيقه كاختبار. مبالغ المزايدة المحجوزة تُنقل منفصلة عن المتاح بعد مطابقتها مع المتصدر. أرصدة المشتريات السابقة غير الموثقة تحتاج مراجعة إثباتات وليست مشتريات موثقة لمجرد وجود رقم.
10. طبّق الملف المراجع:
    `node functions/throne-v2/migrate_wallets.js apply --project=titi-star0 --manifest=wallet-migration-reviewed.json`
    تُصفّر حقول الرصيد في مصدر العرش القديم بعد نقلها، مع علامة انتقال؛ لا يبقى مصدران قابلان للاستخدام. تُحفظ نسخة الحالة السابقة كاملة لكل حساب في `wallet_migrations/{runId}/accounts/{uid}`. إذا انقطع التنفيذ، أعد الأمر بالملف نفسه؛ لا يضيف المبلغ مجدداً. إذا تغيرت اللقطة/ظهر حساب جديد، تتوقف الأداة للمراجعة. لا تعدّل الحسابات المنقولة يدوياً أثناء قفل الانتقال.
11. ثبّت نسخة التطبيق المتوافقة ثم فعّل المزايدة:
    `node functions/throne-v2/admin.js activate --project=titi-star0`
12. الشراء يبقى `purchasesEnabled: false` بعد الانتقال؛ فعّله فقط بعد خطوات المتاجر واختبار الدفع. لا تعِد تشغيل العميل القديم أو وظيفته القديمة كطريقة رجوع بعد نقل الأرصدة. الرجوع يحتاج مراجعة حركة المال التي حدثت بعد القطع.

تتطلب الأدوات بيانات اعتماد Google الإدارية المصرح بها على جهاز المشغّل. لا يحتاج مستخدم التطبيق gcloud أو مفتاح خدمة. التقارير تحتوي معلومات حسابات خاصة؛ لا ترفعها إلى GitHub. لو وُجد ملك الآن، تبقى هويته وموعد نهاية حكمه ومعرّف تتويجه؛ لا يُخصم مبلغ فوزه مجدداً. لا تجري الأداة reset ولا تختصر الوقت.

## استرجاع المدفوعات والمتابعة

Google: وظيفة دورية كل ست ساعات، مع صفحة متابعة API ونافذة تداخل آمنة وسجل آخر نجاح. إذا فشل الاتصال لا يُقدّم المؤشر. أول تشغيل يغطي آخر 29 يوماً؛ بعد توقف أطول يلزم تدقيق تاريخ المتجر الأقدم خارج نافذة API. راقب فشل الوظيفة وتأخر `wallet_operations/google_refunds.checkedUntil`.

Apple: تحقق توقيع الإشعار والمعاملة قبل التسوية، مع دعم التكرار والوصول بترتيب مختلف. استرجاع يصل قبل تسليم العملات يسجل مانعاً، فلا يمكن تسليم الفاتورة بعده. إلغاء الاسترجاع يعكس أثره مرة واحدة. أخطاء التسوية تعيد HTTP 503 لإعادة المحاولة. راقب وصول إشعارات المتجر وإعادة إرسال الإخفاقات.

لا تُسجّل إثباتات المتجر أو رموز App Check في السجلات/المستودع. المستند العالمي للفواتير وسجل التسويات لا يقرأهما العميل ولا يكتبهما. تقارير الانتقال للمدير فقط. القرارات الإدارية المجانية للصندوق تعتمد custom claim `admin: true` موثوقاً من الخادم، ولا تعتمد `users.isAdmin`.

## التحقق المنفّذ وحدوده

نجحت 26 حالة اختبار مالية وقواعد على المحاكي. الاختبارات المالية والقواعد تعمل على Firestore Emulator محلي لمشروع `demo-tini-throne` فقط. تغطي التكرار، المطالبة عبر حساب آخر، حجزين متزامنين، فرق رفع المزايدة، الاسترجاع، تسوية التتويج مرة واحدة، دفع البائع، انتهاء الصندوق، منع تزوير الإدارة/الأرصدة، قيود Sandbox، الدين وعكسه، وترحيل الملك دون إعادة الخصم. تحليل Dart للملفات المعدلة يمر دون مشاكل.

تشغيلها: شغّل محاكي Firestore للمشروع التجريبي، ثم في PowerShell:

```powershell
$env:FIRESTORE_EMULATOR_HOST='127.0.0.1:8080'
$env:GCLOUD_PROJECT='demo-tini-throne'
npm test --prefix functions/throne-v2
```

لم يُختبر دفع فعلي بحساب متجر هنا، ولا وصول إشعار فعلي من Apple، لعدم توفر إعدادات المتجر وصلاحياته في بيئة العمل. اختبارات استجابات Google تستخدم بيانات محاكاة للتحقق من القرارات؛ لا يُدّعى أنها شراء حقيقي. اختبارات الانتظار اليدوي الطويلة مؤجلة كما طلب المالك. لم يُنشر أي شيء إلى Firebase ولم يُطبق الانتقال على حساباته.

## روابط جميع الملفات في الفرع المستقل

- [.gitignore](https://github.com/rojavayekurdistanee-cmyk/tini/blob/codex/tini-wallet-throne-link/.gitignore)
- [docs/wallet-throne-integration.md](https://github.com/rojavayekurdistanee-cmyk/tini/blob/codex/tini-wallet-throne-link/docs/wallet-throne-integration.md)
- [firestore.rules](https://github.com/rojavayekurdistanee-cmyk/tini/blob/codex/tini-wallet-throne-link/firestore.rules)
- [functions/index.js](https://github.com/rojavayekurdistanee-cmyk/tini/blob/codex/tini-wallet-throne-link/functions/index.js)
- [functions/throne-v2/admin.js](https://github.com/rojavayekurdistanee-cmyk/tini/blob/codex/tini-wallet-throne-link/functions/throne-v2/admin.js)
- [functions/throne-v2/box_wallet.js](https://github.com/rojavayekurdistanee-cmyk/tini/blob/codex/tini-wallet-throne-link/functions/throne-v2/box_wallet.js)
- [functions/throne-v2/index.js](https://github.com/rojavayekurdistanee-cmyk/tini/blob/codex/tini-wallet-throne-link/functions/throne-v2/index.js)
- [functions/throne-v2/migrate_wallets.js](https://github.com/rojavayekurdistanee-cmyk/tini/blob/codex/tini-wallet-throne-link/functions/throne-v2/migrate_wallets.js)
- [functions/throne-v2/package-lock.json](https://github.com/rojavayekurdistanee-cmyk/tini/blob/codex/tini-wallet-throne-link/functions/throne-v2/package-lock.json)
- [functions/throne-v2/package.json](https://github.com/rojavayekurdistanee-cmyk/tini/blob/codex/tini-wallet-throne-link/functions/throne-v2/package.json)
- [functions/throne-v2/purchase_verifier.js](https://github.com/rojavayekurdistanee-cmyk/tini/blob/codex/tini-wallet-throne-link/functions/throne-v2/purchase_verifier.js)
- [functions/throne-v2/purchases.js](https://github.com/rojavayekurdistanee-cmyk/tini/blob/codex/tini-wallet-throne-link/functions/throne-v2/purchases.js)
- [functions/throne-v2/refunds.js](https://github.com/rojavayekurdistanee-cmyk/tini/blob/codex/tini-wallet-throne-link/functions/throne-v2/refunds.js)
- [functions/throne-v2/test/rules.test.js](https://github.com/rojavayekurdistanee-cmyk/tini/blob/codex/tini-wallet-throne-link/functions/throne-v2/test/rules.test.js)
- [functions/throne-v2/test/wallet.test.js](https://github.com/rojavayekurdistanee-cmyk/tini/blob/codex/tini-wallet-throne-link/functions/throne-v2/test/wallet.test.js)
- [functions/throne-v2/throne.js](https://github.com/rojavayekurdistanee-cmyk/tini/blob/codex/tini-wallet-throne-link/functions/throne-v2/throne.js)
- [functions/throne-v2/wallet.js](https://github.com/rojavayekurdistanee-cmyk/tini/blob/codex/tini-wallet-throne-link/functions/throne-v2/wallet.js)
- [lib/box_provider.dart](https://github.com/rojavayekurdistanee-cmyk/tini/blob/codex/tini-wallet-throne-link/lib/box_provider.dart)
- [lib/crown_provider.dart](https://github.com/rojavayekurdistanee-cmyk/tini/blob/codex/tini-wallet-throne-link/lib/crown_provider.dart)
- [lib/main.dart](https://github.com/rojavayekurdistanee-cmyk/tini/blob/codex/tini-wallet-throne-link/lib/main.dart)
- [lib/wallet_provider.dart](https://github.com/rojavayekurdistanee-cmyk/tini/blob/codex/tini-wallet-throne-link/lib/wallet_provider.dart)
- [lib/wallet_screen.dart](https://github.com/rojavayekurdistanee-cmyk/tini/blob/codex/tini-wallet-throne-link/lib/wallet_screen.dart)
- [pubspec.lock](https://github.com/rojavayekurdistanee-cmyk/tini/blob/codex/tini-wallet-throne-link/pubspec.lock)
- [pubspec.yaml](https://github.com/rojavayekurdistanee-cmyk/tini/blob/codex/tini-wallet-throne-link/pubspec.yaml)
