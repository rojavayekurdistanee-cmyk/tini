import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'auth_provider.dart' as custom;

class WhoCanSeePostsScreen extends StatefulWidget {
  const WhoCanSeePostsScreen({super.key});

  @override
  State<WhoCanSeePostsScreen> createState() => _WhoCanSeePostsScreenState();
}

class _WhoCanSeePostsScreenState extends State<WhoCanSeePostsScreen> {
  // Structure Colors
  final Color bgColor = const Color(0xFF0F1720);
  final Color surfaceColor = const Color(0xFF1A222C);
  final Color fieldFill = const Color(0xFF1C1C1E);

  // Action Colors
  final Color titiTeal = Colors.teal;
  final Color errorRed = const Color(0xFFE53935);
  final Color highlightRed = const Color(0xFFFF3B30);

  String? _selectedValue;

  @override
  void initState() {
    super.initState();
    final auth = Provider.of<custom.AuthProvider>(context, listen: false);
    _selectedValue = auth.defaultPrivacy; // everyone / friends / only_me
  }

  void _handleSelection(String newValue) async {
    final auth = Provider.of<custom.AuthProvider>(context, listen: false);

    // 1. اذا اختار الأصدقاء وحسابه عام -> نطلع التنبيه
    if (newValue == 'friends' && auth.isPrivate == false) {
      _showFriendsPrivateWarning(newValue);
      return;
    }

    // 2. اذا اختار الجميع وحسابه خاص -> نطلع التنبيه الجديد اللي اتفقنا عليه
    if (newValue == 'everyone' && auth.isPrivate == true) {
      _showEveryonePublicWarning(newValue);
      return;
    }

    // باقي الحالات يحفظ مباشرة
    setState(() => _selectedValue = newValue);
    await auth.updateDefaultPrivacy(newValue);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: surfaceColor,
          content: Text("تم الحفظ", style: TextStyle(color: Colors.white)),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  void _showFriendsPrivateWarning(String pendingValue) {
    final auth = Provider.of<custom.AuthProvider>(context, listen: false);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          "تنبيه الخصوصية",
          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        content: Text(
          "حسابك عام حالياً.\n\nأي شخص يتابعك وتتابعه سيصبح صديقاً ويرى فيديوهات الأصدقاء فقط.\n\nهل تريد جعل حسابك خاصاً لزيادة التحكم؟",
          style: TextStyle(color: Colors.white70, fontSize: 13.5, height: 1.6),
          textAlign: TextAlign.center,
        ),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              setState(() => _selectedValue = pendingValue);
              await auth.updateDefaultPrivacy(pendingValue);
            },
            child: Text("ابق عاماً", style: TextStyle(color: Colors.white54, fontSize: 13)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: titiTeal,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              await auth.updatePrivateAccount(true);
              setState(() => _selectedValue = pendingValue);
              await auth.updateDefaultPrivacy(pendingValue);
            },
            child: Text("اجعله خاصاً", style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showEveryonePublicWarning(String pendingValue) {
    final auth = Provider.of<custom.AuthProvider>(context, listen: false);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          "تنبيه الخصوصية",
          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        content: Text(
          "حسابك خاص حالياً.\n\nعند اختيار \"الجميع\"، المتابعون والأصدقاء فقط هم الذين سيرون فيديوهاتك.\n\nإذا أردت أن يرى أي شخص فيديوهاتك، اجعل حسابك عاماً.",
          style: TextStyle(color: Colors.white70, fontSize: 13.5, height: 1.6),
          textAlign: TextAlign.center,
        ),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              setState(() => _selectedValue = pendingValue);
              await auth.updateDefaultPrivacy(pendingValue);
            },
            child: Text("إبقاء خاص", style: TextStyle(color: Colors.white54, fontSize: 13)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: titiTeal,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              await auth.updatePrivateAccount(false);
              setState(() => _selectedValue = pendingValue);
              await auth.updateDefaultPrivacy(pendingValue);
            },
            child: Text("اجعله عاماً", style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildOption({required String value, required String title, required String subtitle, required IconData icon}) {
    final bool isSelected = _selectedValue == value;
    return InkWell(
      onTap: () => _handleSelection(value),
      child: Container(
        margin: EdgeInsets.only(bottom: 10),
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: isSelected ? fieldFill : surfaceColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? titiTeal : Colors.transparent,
            width: 1.2,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, color: isSelected ? titiTeal : Colors.white54, size: 20),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w600)),
                  SizedBox(height: 3),
                  Text(subtitle, style: TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
            ),
            Icon(
              isSelected ? Icons.check_circle : Icons.circle_outlined,
              color: isSelected ? titiTeal : Colors.white54,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<custom.AuthProvider>(context);
    final String everyoneSubtitle = auth.isPrivate
        ? 'المتابعون والأصدقاء فقط هم من يرون فيديوهاتك'
        : 'يمكن لأي شخص على Titi رؤية فيديوهاتك';

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text("من يمكنه رؤية منشوراتك", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.all(16),
        children: [
          Text("اختر من يمكنه رؤية فيديوهاتك الجديدة تلقائياً", style: TextStyle(color: Colors.white70, fontSize: 13)),
          SizedBox(height: 20),
          _buildOption(value: 'everyone', title: 'الجميع', subtitle: everyoneSubtitle, icon: Icons.public),
          _buildOption(value: 'friends', title: 'الأصدقاء', subtitle: 'المتابعون الذين تتابعهم فقط', icon: Icons.people),
          _buildOption(value: 'only_me', title: 'أنا فقط', subtitle: 'أنت فقط من يمكنه رؤية فيديوهاتك', icon: Icons.lock),
          
          // الملاحظة صارت هون مباشرة تحت انا فقط - بشكل لطيف وواضح
          SizedBox(height: 18),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: surfaceColor.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, color: titiTeal, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    "يمكنك تغيير خصوصية كل فيديو على حدة أثناء النشر.",
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 13.5,
                      height: 1.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 20),
        ],
      ),
    );
  }
}