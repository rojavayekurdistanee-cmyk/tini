# مراجعة نظام عرش Tini v2 وتشغيله يدويًا

## الحالة الفعلية

هذا فرع للمراجعة والاختبار، **وليس إصدارًا جاهزًا للإنتاج**. تم تنفيذ محرك المزاد، المعاملات، الاسترداد، التتويج، مدد الحكم، الشارات، المنافسين، التاريخ، التفاعلات والواجهات. لم يُنشر شيء إلى Firebase ولم تُجرَ أية عملية على بيانات الإنتاج.

هناك مانع مالي مثبت: قواعد `users` الحالية تتيح لصاحب الحساب تعديل `titiBalance`، وهو حقل النقاط الذي كان العرش يقرأه أصلًا. لا يكفي نقل معاملة المزايدة إلى السيرفر إذا كان مصدر الرصيد قابلًا للتزوير من العميل. الاختبار `documented legacy balance-policy blocker cannot silently activate financial bidding` يثبت ذلك محليًا.

للحفاظ على نطاق العرش وعدم تعطيل الوظائف الأخرى، لم نغيّر مصدر الرصيد أو ندمج رصيد المحفظة أو نعدّل ملفات الصناديق. لذلك يبقى استقبال المزايدات المالية وإنشاء الحالة الأولى مقفلين افتراضيًا. يتطلب التفعيل إصلاح سياسة مصدر النقاط وتدقيق الكتابات المشتركة إليه في عمل منفصل، ثم إعادة اختبارات التكامل. **لا تضبط إعداد التفعيل في الإنتاج لتجاوز هذا المانع.**

حقل `titiBalance` القديم وحقل المحفظة `tiniBalance` مختلفان فعليًا. بقيت أسماء التخزين كما هي حفاظًا على البيانات؛ يستخدم عرض العرش اسم Tini/تيني. لم ننفّذ ترحيل أسماء الحقول أو دمج الأرصدة.

## نقطة البداية وحدود Git

- المستودع: `rojavayekurdistanee-cmyk/tini`.
- نقطة البداية الفعلية من أحدث `main`: `befee492751c282485f1e6461f5e90ec4dd024d6`.
- الفرع المقصود: `codex/tini-throne-complete`، أو لاحقة فريدة إذا ظهر تعارض أثناء الرفع.
- لا تعديل أو Commit أو Push أو Merge إلى `main`، ولا Pull Request، ولا Force Push.
- لا ملفات محذوفة أو منقولة، ولا تعديل لاعتماديات Flutter أو حزمة الوظائف الأصلية أو صور الشارات أو ملف `lib/throne_badges.dart`.

## نموذج البيانات

- `throne_data/current`: `schemaVersion: 2`، الحالة `auction` أو `reign`، معرّف المزاد، بداية/نهاية المزاد، المتصدر ومبلغه، الملك وبداية/نهاية حكمه ومعرّف التتويج وأعداد التفاعلات.
- `users/{uid}.titiBalance`: الرصيد المتاح القديم، تنقص منه النقاط عند الحجز.
- `users/{uid}.throneReservedPoints`: حجز العرض النشط الوحيد. لا يُضاف إلى الرصيد المتاح. محمي من كتابة العميل.
- `users/{uid}.throneCoronations` و`throneFormerKing`: نسخ مساعدة يكتبها السيرفر. الاستحقاق المرجعي مستقل في `throne_entitlements`، فلا تُستمد الشارات من بيانات تعليق قابلة للتعديل.
- `throne_requests/{uid}/bids/{requestId}`: إيصال دائم يربط معرّف الطلب بالمزاد والمبلغ والنتيجة. لا تحذف الإيصالات دون تصميم بديل يضمن منع التكرار.
- `throne_ledger/{id}`: عمليات `reserve` و`refund` و`settle`. التسوية لا تخصم المبلغ مرة ثانية؛ فقد خرج أصلًا من الرصيد المتاح عند الحجز.
- `throne_bids/{id}`: سجل عروض غير قابل لكتابة العميل.
- `throne_auctions/{auctionId}/competitors/{uid}`: أعلى عرض لكل مستخدم في المزاد؛ الاستعلام محدود بثلاثة. العروض القديمة معروضة كتاريخ غير محجوز، والمتصدر وحده محجوز أثناء المزاد.
- `throne_reigns/{coronationId}`: سجل كل فترة حكم، المدة والمبلغ والهوية وعدد التتويجات، وعلامة `completed`. القاعة تحمل 20 سجلًا في الصفحة باستخدام cursor.
- `throne_entitlements/{uid}`: استحقاق الشارة الحالية ونهايتها، الاستحقاق الدائم للملك السابق، وعدد مرات التتويج المرجعي.
- `throne_reigns/{id}/reactions/{uid}`: اختيار تفاعل واحد ثابت لكل مستخدم لكل فترة حكم. الإعادة لا ترفع العدادات ولا تمنح نقاطًا.
- `throne_config/runtime`: إعداد خاص بالسيرفر، لا صلاحية للعميل عليه. يسمح بإنشاء الحالة الأولى والمزايدات فقط عندما تكون `enabled: true` و`financialSafetyVersion: 2`. هذا إقرار تشغيلي بعد الإصلاح المالي، **وليس فحصًا آليًا لصحة قواعد الرصيد**. غيابه يعني عدم التفعيل.

## Cloud Functions

كل الوظائف في `europe-west1`:

1. `placeThroneBid`: Callable موثّق مع App Check، يربط الطلب أيضًا بهوية الحساب لمنع إرسال طلب حساب قديم بعد تبديل المستخدم. يعيد الإيصال نفسه عند تكرار الطلب؛ يرفض تغيير مبلغه أو مزاده. يحجز الفرق عند زيادة المتصدر، ويرد حجز المتصدر السابق داخل المعاملة نفسها. يفحص المهلة ثانية بعد القراءات.
2. `syncThrone`: Callable موثّق مع App Check، يحاول إتمام الانتقال المستحق ويرجع الوقت وحالة التفعيل. يستخدمه Flutter لمعايرة العرض وللمزامنة بعد العودة من الخلفية. لا يتولى Timer الجهاز أي انتقال.
3. `advanceThrone`: مهمة كل دقيقة مع ثلاث محاولات إعادة. معاملات المستند المركزي تمنع الملكين أو المزادين المتزامنين. تبدأ مدة الحكم من وقت التتويج الفعلي حتى مع تأخر الجدولة، 24 ساعة للفوز العادي وسبعة أيام لعرض 10,000.
4. `reactToThrone`: Callable موثّق مع App Check، يثبت تفاعلًا واحدًا لكل مستخدم وحكم، ويرفض الحكم المنتهي.

الإيقاف عبر `enabled: false` يمنع عروضًا جديدة؛ يظل إتمام الفترات الموجودة فعالًا حتى لا تترك العملية المالية أو الحكم عالقًا. لا توجد واجهة لإضافة نقاط اعتباطية من العميل. لا توجد استدعاءات داخل المشروع للدالة القديمة `addPointsToCurrentUser`؛ بقي توقيعها للتوافق لكنها ترفض سك النقاط من العميل.

وظائف العرش في codebase مستقل اسمه `throne-v2` ومصدره `functions/throne-v2/`. بقي `functions/index.js` وملف اعتماديات الوظائف الأصلي دون أي تغيير. عُدّل `firebase.json` لإضافة الحزمة المستقلة واستثنائها من حزمة الوظائف الأصلية. المدخل الجديد يهيئ Admin SDK ثم يصدّر وظائف العرش الأربع. تعتمد الحزمة الجديدة على نسختي Firebase المذكورتين في الحد الأدنى لاعتماديات الحزمة الأصلية: `firebase-admin 14.3.0` و`firebase-functions 7.3.2`، مع lockfile مستقل. اختُبرت هذه الحزمة باعتمادياتها المثبتة فعلًا.

رفضت المراجعة التلقائية رفع نسخة معدّلة من المدخل الأصلي لاحتوائه على اعتماد بريد قديم مضمن. لم يُرفع هذا الملف أو تُنقل قيمة الاعتماد؛ فصل الحزمة أزال الحاجة إلى نقله بالكامل، دون تغيير إعداد البريد أو وظائف أخرى.

## الترحيل من العرش القديم

المحرك لا يغيّر حالة قديمة لا تحمل `schemaVersion: 2`. النظام القديم كان ينفق النقاط مباشرة عند كل عرض، ولم يكن سجلّه حجزًا قابلاً للاسترداد. لا يجوز استنتاج تعويضات آلية أو توليد أرصدة من هذا السجل.

قبل أي اعتماد يدوي: احفظ نسخة احتياطية، أوقف العملاء القدامى عن كتابة العرش، راجع الملك والعروض والتسويات القديمة، واعتمد تسوية موثقة لكل رصيد متأثر. بعد اكتمالها فقط، أرشف الحالة القديمة وأزل مستند الحالة المركزية بطريقة إدارية موثقة، ثم اسمح للمحرك بإنشاء مزاد جديد. لا تعِد استخدام معرّف مزاد أو إيصال أو تتويج قديم. لا يتضمن هذا الفرع أي سكربت ينفّذ ترحيلًا إنتاجيًا أو تغييرات أرصدة.

## الفهارس والإعدادات

الفهرس الجديد الوحيد موجود في `firestore.throne.indexes.json`: مجموعة `throne_reigns`، الحقل `completed ASC` ثم `crownedAt DESC` بنطاق Collection.

`firebase.throne.json` إعداد محلي مستقل للمحاكي، لا يستبدل إعداد المشروع الحالي. لا تنشر قائمة الفهارس الجزئية على حساب حذف فهارس موجودة؛ أضف الفهرس إلى القائمة الكاملة المعتمدة أو أنشئه يدويًا، وارفض أي اقتراح حذف لفهرس غير متعلق بالعرش.

المشروع الحالي يفعّل App Check بوضع Debug على Android وApple؛ يحتاج الإصدار الحقيقي إلى إعداد المزوّد المدعوم وتسجيله واختباره على كل منصة. لم نغيّر تهيئة التطبيق أو ننشئ أسرارًا. يجب اختبار مصادقة Callable وApp Check والشبكة في مشروع staging مستقل؛ اختبارات المحاكي لا تثبت صحة إعدادات الإنتاج.

## ترتيب النشر اليدوي لاحقًا — لم يُنفّذ

1. راجع الفرع والفروقات، واختبر نسخة staging مستقلة ونسخة احتياطية من البيانات. أصلح مانع الرصيد، واعتمد الترحيل القديم أولًا. لا تفعّل المزايدات قبل ذلك.
2. أبقِ التفعيل مغلقًا. انشر **codebase العرش المستقل فقط** بعد مراجعة الحزمة والصادرات، مثل:
   ```sh
   firebase deploy --project YOUR_STAGING_PROJECT --only functions:throne-v2
   ```
3. أضف الفهرس الجديد إلى فهارس المشروع الكاملة وانتظر جاهزيته.
4. طبّق القواعد المعتمدة بعد تسوية أثرها على العملاء القدامى. القواعد الجديدة تمنع كتابة العرش المباشرة وتمنع تزوير حقول الحجز. لا تحاول تشغيل عميل قديم يكتب العرش مباشرة معها.
5. اختبر Flutter الجديد مع وظائف السيرفر والقواعد المتوافقة. لا تشغّله مع سيرفر قديم. لا توجد عودة تلقائية إلى الخصم المحلي إذا غابت الوظائف.
6. بعد إصلاح المصدر المالي واكتمال الترحيل واختبارات staging فقط، يضبط المسؤول إعداد التفعيل إداريًا. لا تمنح العميل صلاحية ضبطه.
7. تحقق من مزاد فارغ، عرضين متزامنين، زيادة ذاتية، استرداد، إعادة الطلب، تتويج عادي وفوري، نهاية الحكم، قاعة الملوك والتفاعل المتكرر. قارن الأرصدة والحجز والسجل قبل وبعد، وراقب أخطاء الجدولة وApp Check.

للرجوع: امنع عروضًا جديدة أولًا، واحفظ بيانات v2 وسجلاتها. أكمل أو سوِّ كل حجز موثق من السيرفر قبل أي تغيير مالي. يمكن الرجوع إلى واجهة قراءة متوافقة أو إصلاح السيرفر مع الإبقاء على السجلات؛ **لا تُعد فتح كتابة الرصيد أو العرش من العميل، ولا تستعد منطق الخصم القديم فوق حجوزات v2**. لا تحذف الإيصالات أو سجل الحكم أثناء الرجوع.

## الاختبارات وحدودها

- Flutter الموجود فعليًا: `/workspace/toolchains/flutter/bin/flutter` إصدار 3.47.9، وDart 3.13.7. المسار المطلوب للإصدار 3.47.6 غير موجود؛ لم يُثبَّت أو يُغيَّر أي إصدار.
- `flutter pub get`: نجح دون تعديل ملفات الاعتماديات المتتبعة.
- `dart format`: نُفّذ على ملفات العرش الجديدة والمعدّلة المنظمة واختبار Flutter. فُحصت ملفات البروفايل والتعليقات والقسم القديم بـ`--output=none` للحفاظ على فروقاتها الصغيرة وعدم إعادة تنسيق آلاف الأسطر القديمة.
- `node --check`: نجح للمدخل ووحدة العرش واختبار السيرفر.
- Firebase Firestore Emulator على loopback ومشروع `demo-tini-throne` فقط: **21 اختبارًا ناجحًا** تشمل اختبارات المعاملات والقواعد، بما فيها التزامن والحالات المالية وموانع التفعيل. الاختبارات ترفض عنوانًا غير محلي أو اسم مشروع غير `demo-*`.
- `flutter test --no-pub`: 12 اختبارًا ناجحًا. فحص العداد وانتهاء الوقت والعودة من الخلفية، استحقاق الشارات، احتفال خفيف، والشارتين الأصليتين بعروض 240/320/600/1024 ومقياسي نص 1 و2.
- ملف `.env` مفقود في النسخة الأصلية رغم تسجيله ضمن assets. استُخدم ملف محلي فارغ مؤقتًا لاختبارات تجميع assets ثم أُزيل؛ لم يُرفع أو يُضف أي سر.
- `flutter analyze --no-pub`: لا أخطاء تحليل. توجد تشخيصات قديمة في المشروع؛ المقارنة مع نقطة البداية: 753 تشخيصًا (125 تحذيرًا و628 ملاحظة)، مقابل 742 (123 تحذيرًا و619 ملاحظة) بعد التعديل، دون تشخيصات جديدة. تحليل ملفات العرش الجديدة والمنظمة واختبارها وحدها أعطى `No issues found`. أُجريت المقارنة بملف assets محلي فارغ في النسختين لتساوي الظروف. لا يوصف التحليل العام بأنه نظيف.
- فشل التشغيل الأول للتحليل بسبب مجلد `.dartServer` في home للقراءة فقط؛ أُعيد بنجاح باستخدام `ANALYZER_STATE_LOCATION_OVERRIDE` داخل `work/`. لم تُغيَّر متغيرات HOME.
- لا أجهزة Android أو iOS فعلية متصلة. لا تدّعي اختبارات Widget ضمان كل الأجهزة أو الأداء الرسومي على CPU/GPU ضعيف. لم يتم بناء/تشغيل التطبيق الكامل على Android/iOS/Web/Windows أو اختبار الشبكات الحقيقية وApp Check والإشعارات.
- المنصات الموجودة في المشروع Android/iOS/Web/Windows، وحد Android الأدنى 24 وiOS 13 وفق الملفات الحالية؛ لم نغيّرها. واجهات العرش الجديدة تستخدم Flutter القياسي؛ التوافق الفعلي يحتاج تجربة على المنصات المبنية وإعداداتها الحالية.

## عدم الانحدار

تم التحقق من بقاء ملف الشارات وصور PNG وحلقة النار دون تعديل، ومن بقاء زر المتابعة وفتح البروفايل وإدخال العرض وحالات التحميل ورقم التاج وقسم المكافآت في الفروقات. ظهور شارة العرش بجانب الاسم لا يستبدل الشارات القديمة. التحقق التفاعلي للمتابعة وتسجيل الدخول والتنقل والبروفايل والتعليقات ووظائف الأرصدة الأخرى لم يتم على أجهزة حقيقية، ولا يُدّعى نجاحه باختبارات الوحدات.

الاحتفال قصير وغير حاجب للتنقل، يظهر عند تغيّر معرّف تتويج حي بعد المزامنة الأولى، ويُحفظ آخر معرّف شوهد لمنع التكرار. الشرارات 12 جسيمًا فقط؛ عند تقليل الحركة يبقى العرض الملكي ثابتًا. اشتراكات الاستحقاق مشتركة بين الأسماء المتكررة وتُلغى حين لا يوجد مستمع مرئي.

## الاعتماد

راجع الفرع بالمتصفح وقارن مع نقطة البداية. خذ الملفات بمساراتها الأصلية بعد مراجعة التبعيات والقواعد. احتفظ بالشارات وأصولها وإعدادات المشروع. أي نقل إلى `main` أو نشر أو إصلاح للمانع المالي أو ترحيل أرصدة قرار مستقل للمستخدم؛ لم يُجرَ دمج تلقائي أو Pull Request.

## أوامر التحقق المنفذة

```sh
source /workspace/toolchains/activate-tini.sh
/workspace/toolchains/flutter/bin/flutter pub get
/workspace/toolchains/flutter/bin/dart format lib/crown_provider.dart lib/throne_social.dart lib/throne_celebration.dart lib/throne_earned_badge.dart lib/throne_countdown.dart lib/tini_throne_fullscreen.dart test/throne_ui_test.dart
/workspace/toolchains/flutter/bin/dart format --output=none lib/profile_screen.dart lib/post_comments_sheet.dart lib/throne_section.dart
ANALYZER_STATE_LOCATION_OVERRIDE=/workspace/work/dart-server /workspace/toolchains/flutter/bin/flutter analyze --no-pub
ANALYZER_STATE_LOCATION_OVERRIDE=/workspace/work/dart-server /workspace/toolchains/flutter/bin/flutter analyze --no-pub lib/crown_provider.dart lib/throne_celebration.dart lib/throne_countdown.dart lib/throne_earned_badge.dart lib/throne_social.dart lib/tini_throne_fullscreen.dart test/throne_ui_test.dart
/workspace/toolchains/flutter/bin/flutter test --no-pub
node --check functions/throne-v2/index.js
node --check functions/throne-v2/throne.js
node --check functions/test/throne.test.js
npm ci --ignore-scripts --prefix functions/throne-v2
FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 GCLOUD_PROJECT=demo-tini-throne node --test functions/test/throne.test.js
git diff --check
```

شُغّل محاكي Firestore محليًا بأداة Firebase CLI 15.35.0 المثبتة في مجلد عمل مؤقت خارج المستودع، مع `--project demo-tini-throne --only firestore`. لتكرار الاختبارات استخدم إعداد `firebase.throne.json` المحلي، وملف `.env` اختباريًا فارغًا عند الحاجة إلى تجميع assets فقط. لا تستخدم حسابات أو أرصدة حقيقية.

## قائمة الملفات الكاملة

لم يتم حذف أي ملف أصلي أو نقله. جميع المسارات أدناه أصلها `/workspace/tini/`.

### الملفات المعدّلة (7)

| المسار الكامل | النوع والوظيفة والتحقق | رابط الملف |
|---|---|---|
| `/workspace/tini/firebase.json` | معدّل: إضافة codebase مستقل للعرش مع إبقاء codebase الأصلي واستثناء الحزمة الجديدة منه؛ لم يتغير مدخل الوظائف الأصلي. | [فتح الملف](https://github.com/rojavayekurdistanee-cmyk/tini/blob/codex/tini-throne-complete/firebase.json) |
| `/workspace/tini/firestore.rules` | معدّل: حماية حالة العرش والاستحقاق والسجلات وحقول الحجز؛ اختبارات القواعد ناجحة، مع بقاء مانع مصدر الرصيد موثقًا. | [فتح الملف](https://github.com/rojavayekurdistanee-cmyk/tini/blob/codex/tini-throne-complete/firestore.rules) |
| `/workspace/tini/lib/crown_provider.dart` | معدّل: طلبات السيرفر، وقت العرض، التحميل، إعادة الطلب المحفوظة، وإزالة الخصم والتصفير المحليين؛ التحليل المخصص نظيف. | [فتح الملف](https://github.com/rojavayekurdistanee-cmyk/tini/blob/codex/tini-throne-complete/lib/crown_provider.dart) |
| `/workspace/tini/lib/post_comments_sheet.dart` | معدّل: إضافة شارة استحقاق حقيقية بجانب الاسم مع إبقاء الشارة القديمة؛ التحليل دون أخطاء جديدة، والتجربة التفاعلية مؤجلة. | [فتح الملف](https://github.com/rojavayekurdistanee-cmyk/tini/blob/codex/tini-throne-complete/lib/post_comments_sheet.dart) |
| `/workspace/tini/lib/profile_screen.dart` | معدّل: إضافة شارة الاستحقاق بجانب الاسم مع ضبط الاسم الطويل؛ التحليل دون أخطاء جديدة، والتجربة التفاعلية مؤجلة. | [فتح الملف](https://github.com/rojavayekurdistanee-cmyk/tini/blob/codex/tini-throne-complete/lib/profile_screen.dart) |
| `/workspace/tini/lib/throne_section.dart` | معدّل: توافق القسم القديم مع حالتي المتصدر والملك والعداد الآمن واسم Tini ورسائل الخطأ؛ دون استدعاءات مكسورة. | [فتح الملف](https://github.com/rojavayekurdistanee-cmyk/tini/blob/codex/tini-throne-complete/lib/throne_section.dart) |
| `/workspace/tini/lib/tini_throne_fullscreen.dart` | معدّل: ربط حالة المزاد والحكم والشارة والعداد والأقسام الاجتماعية مع إبقاء النار والمتابعة والمكافآت؛ التحليل المخصص نظيف. | [فتح الملف](https://github.com/rojavayekurdistanee-cmyk/tini/blob/codex/tini-throne-complete/lib/tini_throne_fullscreen.dart) |

### الملفات الجديدة (13)

| المسار الكامل | النوع والوظيفة والتحقق | رابط الملف |
|---|---|---|
| `/workspace/tini/docs/throne-v2-review.md` | جديد: التصميم والمانع المالي والترحيل والنشر والرجوع والتحقق وقائمة التسليم الكاملة. | [فتح الملف](https://github.com/rojavayekurdistanee-cmyk/tini/blob/codex/tini-throne-complete/docs/throne-v2-review.md) |
| `/workspace/tini/firebase.throne.json` | جديد: إعداد محاكي مستقل للاختبارات المحلية فقط، لا يستبدل إعداد المشروع. | [فتح الملف](https://github.com/rojavayekurdistanee-cmyk/tini/blob/codex/tini-throne-complete/firebase.throne.json) |
| `/workspace/tini/firestore.throne.indexes.json` | جديد: تعريف الفهرس الإضافي المحدود لقاعة الملوك، مع وجوب دمجه يدويًا في قائمة الفهارس الكاملة. | [فتح الملف](https://github.com/rojavayekurdistanee-cmyk/tini/blob/codex/tini-throne-complete/firestore.throne.indexes.json) |
| `/workspace/tini/functions/test/throne.test.js` | جديد: اختبارات Firestore Emulator للمال والتزامن والمهل والتتويج والقواعد والتاريخ وموانع التفعيل؛ 21 ناجحًا. | [فتح الملف](https://github.com/rojavayekurdistanee-cmyk/tini/blob/codex/tini-throne-complete/functions/test/throne.test.js) |
| `/workspace/tini/functions/throne-v2/index.js` | جديد: مدخل مستقل يهيئ Admin SDK ويصدر وظائف العرش الأربع فقط؛ فحص JavaScript واختبارات الحزمة ناجحة. | [فتح الملف](https://github.com/rojavayekurdistanee-cmyk/tini/blob/codex/tini-throne-complete/functions/throne-v2/index.js) |
| `/workspace/tini/functions/throne-v2/package-lock.json` | جديد: تثبيت الاعتماديات المتعدية للحزمة المستقلة بصورة قابلة للتكرار؛ npm ci نجح واختُبرت الحزمة المثبتة. | [فتح الملف](https://github.com/rojavayekurdistanee-cmyk/tini/blob/codex/tini-throne-complete/functions/throne-v2/package-lock.json) |
| `/workspace/tini/functions/throne-v2/package.json` | جديد: اعتماديات Firebase لحزمة العرش المستقلة فقط، دون تعديل الحزمة الأصلية أو Flutter. | [فتح الملف](https://github.com/rojavayekurdistanee-cmyk/tini/blob/codex/tini-throne-complete/functions/throne-v2/package.json) |
| `/workspace/tini/functions/throne-v2/throne.js` | جديد: معاملات المزاد والحجز والاسترداد والتتويج والجدولة والتفاعل؛ يستدعيه المدخل المستقل وتغطيه 21 تجربة على المحاكي. | [فتح الملف](https://github.com/rojavayekurdistanee-cmyk/tini/blob/codex/tini-throne-complete/functions/throne-v2/throne.js) |
| `/workspace/tini/lib/throne_celebration.dart` | جديد: احتفال باثني عشر جسيمًا مع صورة واسم وتاج؛ يستخدمه القسم الاجتماعي، ومختبر مع الحركة المخففة. | [فتح الملف](https://github.com/rojavayekurdistanee-cmyk/tini/blob/codex/tini-throne-complete/lib/throne_celebration.dart) |
| `/workspace/tini/lib/throne_countdown.dart` | جديد: عداد عرض مستقل يعالج الخلفية والعودة ولا يكتب إلى Firebase؛ يستخدمه عرضا العرش ومختبر. | [فتح الملف](https://github.com/rojavayekurdistanee-cmyk/tini/blob/codex/tini-throne-complete/lib/throne_countdown.dart) |
| `/workspace/tini/lib/throne_earned_badge.dart` | جديد: استحقاق السيرفر، مؤقت انتهاء الشارة، واشتراك مشترك لكل مستخدم؛ تستخدمه شاشة العرش والبروفايل والتعليقات، ومنطقه مختبر. | [فتح الملف](https://github.com/rojavayekurdistanee-cmyk/tini/blob/codex/tini-throne-complete/lib/throne_earned_badge.dart) |
| `/workspace/tini/lib/throne_social.dart` | جديد: المنافسون والتفاعلات وقاعة الملوك ذات الصفحات والاحتفال ومنع تكراره وتأكيد الطلب؛ تستدعيه الشاشة الكاملة. | [فتح الملف](https://github.com/rojavayekurdistanee-cmyk/tini/blob/codex/tini-throne-complete/lib/throne_social.dart) |
| `/workspace/tini/test/throne_ui_test.dart` | جديد: 12 اختبار Flutter لاستحقاق الشارات والعداد ودورة الحياة والاحتفال والمقاسات والنصوص الكبيرة. | [فتح الملف](https://github.com/rojavayekurdistanee-cmyk/tini/blob/codex/tini-throne-complete/test/throne_ui_test.dart) |

