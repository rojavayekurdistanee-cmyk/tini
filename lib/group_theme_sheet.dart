import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';

// ============ ألوانك انت ============
const Color kBg = Color(0xFF0F1720);
const Color kSurface = Color(0xFF1A222C);
const Color kFieldFill = Color(0xFF1C1C1E);
const Color kErrorRed = Color(0xFFE53935);
const Color kLinkRed = Color(0xFFFF3B30);
const Color kTeal = Colors.teal;

// ============ موديلات ============
class ChatTheme {
  final String id;
  final String nameAr;
  final String imageUrl;
  final Color bubbleMe;
  final Color bubbleOther;
  ChatTheme({required this.id, required this.nameAr, required this.imageUrl, required this.bubbleMe, required this.bubbleOther});
}

class ChatFont {
  final String id;
  final String name;
  final TextStyle style;
  ChatFont({required this.id, required this.name, required this.style});
}

final List<ChatTheme> kThemes = [
  ChatTheme(id: 'glow_pup', nameAr: 'Glow Pup', imageUrl: 'https://images.unsplash.com/photo-1560769629-975ec94e6a86?w=300', bubbleMe: Color(0xFFF8BBD0), bubbleOther: Color(0xFF212121)),
  ChatTheme(id: 'superman', nameAr: 'سوبر جيرل', imageUrl: 'https://images.unsplash.com/photo-1600480505021-e9cfb05527f1?w=300', bubbleMe: Color(0xFFEF5350), bubbleOther: Color(0xFF212121)),
  ChatTheme(id: 'odyssey', nameAr: 'الأوديسة', imageUrl: 'https://images.unsplash.com/photo-1518709268805-4e9042af9f23?w=300', bubbleMe: Color(0xFFB0BEC5), bubbleOther: Color(0xFF212121)),
  ChatTheme(id: 'olivia', nameAr: 'أوليفيا رودريجو', imageUrl: 'https://images.unsplash.com/photo-1518531933037-91b2f5f229cc?w=300', bubbleMe: Color(0xFFF8BBD0), bubbleOther: Color(0xFF212121)),
  ChatTheme(id: 'backrooms', nameAr: 'Backrooms', imageUrl: 'https://images.unsplash.com/photo-1519608487953-e999c86e7455?w=300', bubbleMe: Color(0xFFD7CCC8), bubbleOther: Color(0xFF212121)),
  ChatTheme(id: 'avatar', nameAr: 'أفاتار', imageUrl: 'https://images.unsplash.com/photo-1506744038136-46273834b3fb?w=300', bubbleMe: Color(0xFFA5D6A7), bubbleOther: Color(0xFF212121)),
  ChatTheme(id: ' 【entity-maluma¦canonical_name=Maluma】', nameAr: ' 【entity-Maluma¦canonical_name=Maluma】', imageUrl: 'https://images.unsplash.com/photo-1493225457124-a3eb161ffa5f?w=300', bubbleMe: Color(0xFFCE93D8), bubbleOther: Color(0xFF212121)),

  ChatTheme(id: 'velvet_night', nameAr: 'مخمل الليل', imageUrl: 'https://images.unsplash.com/photo-1470071459604-3b5ec3a7fe05?w=300', bubbleMe: Color(0xFF8E24AA), bubbleOther: Color(0xFF1A1A1A)),
  ChatTheme(id: 'ocean_breeze', nameAr: 'نسيم البحر', imageUrl: 'https://images.unsplash.com/photo-1507525428034-b723cf961d3e?w=400', bubbleMe: Color(0xFF00ACC1), bubbleOther: Color(0xFF263238)),
  ChatTheme(id: 'crimson_dusk', nameAr: 'شفق قرمزي', imageUrl: 'https://images.unsplash.com/photo-1501973801540-537f08ccae7b?w=400', bubbleMe: Color(0xFFD81B60), bubbleOther: Color(0xFF212121)),
  ChatTheme(id: 'nebula_blue', nameAr: 'سديم أزرق', imageUrl: 'https://images.unsplash.com/photo-1531306728370-e2ebd9d7bb99?w=400', bubbleMe: Color(0xFF3949AB), bubbleOther: Color(0xFF121212)),
  ChatTheme(id: 'mossy_rock', nameAr: 'صخرة طحلبية', imageUrl: 'https://images.unsplash.com/photo-1448375240586-882707db888b?w=400', bubbleMe: Color(0xFF558B2F), bubbleOther: Color(0xFF212121)),
  ChatTheme(id: 'shinjuku', nameAr: 'شينجوكو', imageUrl: 'https://images.unsplash.com/photo-1540959733332-eab4deabeeaf?w=400', bubbleMe: Color(0xFF00BCD4), bubbleOther: Color(0xFF000000)),
  ChatTheme(id: 'cotton_candy_sky', nameAr: 'غزل بنات', imageUrl: 'https://images.unsplash.com/photo-1519681393784-d120267933ba?w=400', bubbleMe: Color(0xFFF48FB1), bubbleOther: Color(0xFF2D2D2D)),
  ChatTheme(id: 'golden_dune', nameAr: 'ذهب الصحراء', imageUrl: 'https://images.unsplash.com/photo-1509316785289-025f5b846b35?w=400', bubbleMe: Color(0xFFFFB300), bubbleOther: Color(0xFF212121)),
  ChatTheme(id: 'lavender_field', nameAr: 'حقل خزامى', imageUrl: 'https://images.unsplash.com/photo-1499002238440-d264edd596ec?w=400', bubbleMe: Color(0xFF7E57C2), bubbleOther: Color(0xFF212121)),
  ChatTheme(id: 'sakura_day', nameAr: 'ساكورا', imageUrl: 'https://images.unsplash.com/photo-1522383225653-ed111181a951?w=400', bubbleMe: Color(0xFFFFAB91), bubbleOther: Color(0xFF3E2723)),
  ChatTheme(id: 'ice_lagoon', nameAr: 'بحيرة جليدية', imageUrl: 'https://images.unsplash.com/photo-1491002052546-bf38f186af56?w=400', bubbleMe: Color(0xFF4FC3F7), bubbleOther: Color(0xFF0D1B2A)),
  ChatTheme(id: 'jungle_ink', nameAr: 'حبر الغابة', imageUrl: 'https://images.unsplash.com/photo-1518837695005-2083093ee35b?w=400', bubbleMe: Color(0xFF2E7D32), bubbleOther: Color(0xFF1B1B1B)),
  ChatTheme(id: 'violet_storm', nameAr: 'عاصفة بنفسجية', imageUrl: 'https://images.unsplash.com/photo-1534796636912-3b95b3ab5986?w=400', bubbleMe: Color(0xFFAB47BC), bubbleOther: Color(0xFF212121)),
  ChatTheme(id: 'coffee_late', nameAr: 'لاتيه', imageUrl: 'https://images.unsplash.com/photo-1447933601403-0c6688de566e?w=400', bubbleMe: Color(0xFFA1887F), bubbleOther: Color(0xFF3E2723)),
  ChatTheme(id: 'mango_juice', nameAr: 'عصير مانجو', imageUrl: 'https://images.unsplash.com/photo-1551024506-0bccd828d307?w=400', bubbleMe: Color(0xFFFF6F00), bubbleOther: Color(0xFF212121)),
  ChatTheme(id: 'ruby_flame', nameAr: 'لهب ياقوتي', imageUrl: 'https://images.unsplash.com/photo-1519125323398-675f0ddb6308?w=400', bubbleMe: Color(0xFFE53935), bubbleOther: Color(0xFF212121)),
  ChatTheme(id: 'moon_dust', nameAr: 'غبار القمر', imageUrl: 'https://images.unsplash.com/photo-1532012197267-da84d127e765?w=400', bubbleMe: Color(0xFFB0BEC5), bubbleOther: Color(0xFF212121)),
  ChatTheme(id: 'noir_city', nameAr: 'مدينة نوار', imageUrl: 'https://images.unsplash.com/photo-1514565131-fce0801e5785?w=400', bubbleMe: Color(0xFF607D8B), bubbleOther: Color(0xFF0F0F0F)),
  ChatTheme(id: 'aqua_pearl', nameAr: 'لؤلؤة مائية', imageUrl: 'https://images.unsplash.com/photo-1518895949257-7621c3c786d7?w=400', bubbleMe: Color(0xFF80DEEA), bubbleOther: Color(0xFF212121)),
  ChatTheme(id: 'forest_soul', nameAr: 'روح الغابة', imageUrl: 'https://images.unsplash.com/photo-1473448912268-2022ce9509d8?w=400', bubbleMe: Color(0xFF26A69A), bubbleOther: Color(0xFF212121)),
];


final List<ChatFont> kFonts = [
  // عربي
  ChatFont(id: 'ar1', name: 'عادي', style: GoogleFonts.tajawal(fontSize: 16)),
  ChatFont(id: 'ar2', name: 'عريض', style: GoogleFonts.cairo(fontSize: 20, fontWeight: FontWeight.w900)),
  ChatFont(id: 'ar3', name: 'نسخ', style: GoogleFonts.amiri(fontSize: 20, height: 1.4)),
  ChatFont(id: 'ar4', name: 'مزخرف', style: GoogleFonts.lalezar(fontSize: 23)),
  ChatFont(id: 'ar5', name: 'كوفي', style: GoogleFonts.reemKufi(fontSize: 18, letterSpacing: 1)),
  ChatFont(id: 'ar_ruqaa', name: 'رقعة', style: GoogleFonts.arefRuqaa(fontSize: 22, fontWeight: FontWeight.w700)),
  ChatFont(id: 'ar_katibeh', name: 'كتيبة', style: GoogleFonts.katibeh(fontSize: 26)),
  ChatFont(id: 'ar_lemonada', name: 'ليمونادا', style: GoogleFonts.lemonada(fontSize: 16, fontWeight: FontWeight.w600)),
  ChatFont(id: 'ar_messiri', name: 'المسيري', style: GoogleFonts.elMessiri(fontSize: 20, fontWeight: FontWeight.w700)),
  ChatFont(id: 'ar_markazi', name: 'مركزي', style: GoogleFonts.markaziText(fontSize: 23, fontWeight: FontWeight.w600)),

  // English
  ChatFont(id: 'en1', name: 'Default', style: GoogleFonts.roboto(fontSize: 16)),
  ChatFont(id: 'en2', name: 'Typewriter', style: GoogleFonts.courierPrime(fontSize: 15, fontWeight: FontWeight.bold)),
  ChatFont(id: 'en3', name: 'Signature', style: GoogleFonts.dancingScript(fontSize: 22, fontWeight: FontWeight.w600)),
  ChatFont(id: 'en4', name: 'Poster', style: GoogleFonts.bebasNeue(fontSize: 24, letterSpacing: 1)),
  ChatFont(id: 'en5', name: 'Wide', style: GoogleFonts.montserrat(fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 4)),
  ChatFont(id: 'en_creep', name: 'Creepy', style: GoogleFonts.creepster(fontSize: 24)),
  ChatFont(id: 'en_bungee', name: 'Bungee', style: GoogleFonts.bungee(fontSize: 18)),
  ChatFont(id: 'en_pixel', name: 'Pixel', style: GoogleFonts.pressStart2p(fontSize: 12)),
  ChatFont(id: 'en_rubik_puddles', name: 'Puddles', style: GoogleFonts.rubikPuddles(fontSize: 22)),
  ChatFont(id: 'en_bangers', name: 'Bangers', style: GoogleFonts.bangers(fontSize: 24, letterSpacing: 1)),
];

class GroupThemeSheet {
  // === هون التعديل الأساسي - صار خاص بكل يوزر ===
  static Future<void> show(BuildContext context, String groupId) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    // نقرا ثيم هذا الشخص فقط
    final doc = await FirebaseFirestore.instance
    .collection('users')
    .doc(uid)
    .collection('groupThemes')
    .doc(groupId)
    .get();

    final currentThemeId = (doc.data()?['themeId']?? 'olivia') as String;
    final currentFontId = (doc.data()?['fontId']?? 'default') as String;
    final hasExistingTheme = doc.exists;

    if (!context.mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ThemeSheetContent(groupId: groupId, initTheme: currentThemeId, initFont: currentFontId, hasExistingTheme: hasExistingTheme),
    );
  }
}

class _ThemeSheetContent extends StatefulWidget {
  final String groupId;
  final String initTheme;
  final String initFont;
  final bool hasExistingTheme;
  const _ThemeSheetContent({required this.groupId, required this.initTheme, required this.initFont, required this.hasExistingTheme});
  @override
  State<_ThemeSheetContent> createState() => _ThemeSheetContentState();
}

class _ThemeSheetContentState extends State<_ThemeSheetContent> with SingleTickerProviderStateMixin {
  late TabController _tab;
  late String selectedThemeId;
  late String selectedFontId;
  bool isPreview = false;
  ChatTheme get selectedTheme => kThemes.firstWhere((t) => t.id == selectedThemeId, orElse: () => kThemes[3]);

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    selectedThemeId = widget.initTheme;
    selectedFontId = widget.initFont;
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.58,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: kSurface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              SizedBox(height: 12),
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white54, borderRadius: BorderRadius.circular(2))),
              SizedBox(height: 16),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Center(child: Text('تخصيص', style: TextStyle(color: Colors.white, fontFamily: 'Tajawal', fontWeight: FontWeight.bold, fontSize: 18))),
                    if (widget.hasExistingTheme)
                      Align(
                        alignment: Alignment.centerRight,
                        child: Container(
                          height: 32,
                          child: TextButton(
                            style: TextButton.styleFrom(
                              backgroundColor: kFieldFill,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                              minimumSize: Size(0, 32),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: () async {
                              final uid = FirebaseAuth.instance.currentUser!.uid;
                              await FirebaseFirestore.instance
                              .collection('users')
                              .doc(uid)
                              .collection('groupThemes')
                              .doc(widget.groupId)
                              .delete();
                              if (mounted) Navigator.pop(context);
                            },
                            child: Text('إزالة السمة', style: TextStyle(color: kErrorRed, fontFamily: 'Tajawal', fontWeight: FontWeight.bold, fontSize: 11)),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(height: 12),
              if (!isPreview)
                TabBar(
                  controller: _tab,
                  indicatorColor: Colors.white,
                  indicatorWeight: 2.5,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white54,
                  labelStyle: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.bold, fontSize: 15),
                  tabs: [Tab(text: 'السمة'), Tab(text: 'الخط')],
                ),
              if (!isPreview) Divider(height: 1, color: Colors.white12),
              Expanded(
                child: isPreview? _buildPreview() : TabBarView(
                  controller: _tab,
                  children: [_buildThemeGrid(scrollController), _buildFontGrid(scrollController)],
                ),
              ),
              _buildBottomButtons(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildThemeGrid(ScrollController sc) {
    return GridView.builder(
      controller: sc,
      padding: EdgeInsets.all(16),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 12, mainAxisSpacing: 16, childAspectRatio: 0.62),
      itemCount: kThemes.length,
      itemBuilder: (c, i) {
        final t = kThemes[i];
        final isSelected = t.id == selectedThemeId;
        return GestureDetector(
          onTap: () => setState(() => selectedThemeId = t.id),
          child: Column(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: isSelected? kTeal : Colors.transparent, width: 3),
                    image: DecorationImage(image: NetworkImage(t.imageUrl), fit: BoxFit.cover),
                  ),
                ),
              ),
              SizedBox(height: 6),
              Text(t.nameAr, maxLines: 2, textAlign: TextAlign.center, style: TextStyle(color: isSelected? kTeal : Colors.white70, fontFamily: 'Tajawal', fontSize: 12, fontWeight: isSelected? FontWeight.bold : FontWeight.normal)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFontGrid(ScrollController sc) {
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Text('اختر خط دردشة مخصصًا ', style: TextStyle(color: Colors.white70, fontFamily: 'Tajawal', fontSize: 12)),
            ],
          ),
        ),
        Expanded(
          child: GridView.builder(
            controller: sc,
            padding: EdgeInsets.symmetric(horizontal: 16),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 1.6),
            itemCount: kFonts.length,
            itemBuilder: (c, i) {
              final f = kFonts[i];
              final isSelected = f.id == selectedFontId;
              return GestureDetector(
                onTap: () => setState(() => selectedFontId = f.id),
                child: Container(
                  decoration: BoxDecoration(
                    color: kFieldFill,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: isSelected? kTeal : Colors.transparent, width: 3),
                  ),
                  child: Center(child: Text(f.name, style: f.style.copyWith(color: Colors.white))),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPreview() {
    return Container(
      decoration: BoxDecoration(image: DecorationImage(image: NetworkImage(selectedTheme.imageUrl), fit: BoxFit.cover)),
      child: ListView(
        padding: EdgeInsets.all(16),
        children: [
          SizedBox(height: 20),
          Center(child: Text('جارِ معاينة ${selectedTheme.nameAr}', style: TextStyle(color: Colors.white, fontFamily: 'Tajawal', fontWeight: FontWeight.bold, fontSize: 16, shadows: [Shadow(color: Colors.black, blurRadius: 4)]))),
          SizedBox(height: 40),
          Align(alignment: Alignment.centerLeft, child: Container(padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12), decoration: BoxDecoration(color: selectedTheme.bubbleMe, borderRadius: BorderRadius.circular(22)), child: Text('تقوم كل سمة بإنشاء تجربة فريدة.', style: TextStyle(color: Colors.black, fontFamily: 'Tajawal')))),
          SizedBox(height: 16),
          Align(alignment: Alignment.centerLeft, child: Container(padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12), decoration: BoxDecoration(color: selectedTheme.bubbleMe, borderRadius: BorderRadius.circular(22)), child: Text('ستظهر لك الرسائل التي تقوم بإرسالها بهذا اللون.', style: TextStyle(color: Colors.black, fontFamily: 'Tajawal')))),
          SizedBox(height: 8),
          Center(child: Text('٥:٠٧ م', style: TextStyle(color: Colors.white70, fontSize: 11))),
          SizedBox(height: 8),
          Align(alignment: Alignment.centerRight, child: Container(padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12), decoration: BoxDecoration(color: selectedTheme.bubbleOther, borderRadius: BorderRadius.circular(22)), child: Text('والرسائل التي تتلقاها من أشخاص آخرين بهذا اللون.', style: TextStyle(color: Colors.white, fontFamily: 'Tajawal')))),
          SizedBox(height: 16),
          Align(alignment: Alignment.centerLeft, child: Container(padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12), decoration: BoxDecoration(color: selectedTheme.bubbleMe, borderRadius: BorderRadius.circular(22)), child: Text('اضغط على "تطبيق" لاختيار هذه السمة أو على "إلغاء" لمعاينة السمات الأخرى.', style: TextStyle(color: Colors.black, fontFamily: 'Tajawal')))),
        ],
      ),
    );
  }

  Widget _buildBottomButtons() {
    return Container(
      color: kSurface,
      padding: EdgeInsets.fromLTRB(16, 12, 16, 30),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: kFieldFill, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), padding: EdgeInsets.symmetric(vertical: 16)),
              onPressed: () {
                if (isPreview) {
                  setState(() => isPreview = false);
                } else {
                  setState(() => isPreview = true);
                }
              },
              child: Text(isPreview? 'إلغاء' : 'معاينة', style: TextStyle(color: Colors.white, fontFamily: 'Tajawal', fontWeight: FontWeight.bold)),
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: kTeal, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), padding: EdgeInsets.symmetric(vertical: 16)),
              onPressed: () async {
                if (!isPreview) {
                  setState(() => isPreview = true);
                  return;
                }
                // === هون صار الحفظ خاص بكل يوزر ===
                final uid = FirebaseAuth.instance.currentUser!.uid;
                await FirebaseFirestore.instance
                .collection('users')
                .doc(uid)
                .collection('groupThemes')
                .doc(widget.groupId)
                .set({
                  'themeId': selectedThemeId,
                  'fontId': selectedFontId,
                  'updatedAt': FieldValue.serverTimestamp(),
                }, SetOptions(merge: true));

                if (mounted) Navigator.pop(context);
              },
              child: Text('تطبيق', style: TextStyle(color: Colors.white, fontFamily: 'Tajawal', fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}