import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class PasswordManagementScreen extends StatefulWidget {
  const PasswordManagementScreen({Key? key}) : super(key: key);

  @override
  _PasswordManagementScreenState createState() => _PasswordManagementScreenState();
}

class _PasswordManagementScreenState extends State<PasswordManagementScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _currentPasswordController = TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();
  
  bool _isCurrentObscured = true;
  bool _isNewObscured = true;
  bool _isConfirmObscured = true;
  bool _isLoading = false; // لإدارة حالة التحميل داخل الزر

  // فحص نوع تسجيل الدخول
  bool get _isPasswordUser {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    return user.providerData.any((info) => info.providerId == 'password');
  }

  String get _providerName {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return "";
    if (user.providerData.any((info) => info.providerId == 'google.com')) return "Google";
    if (user.providerData.any((info) => info.providerId == 'phone')) return "رقم الهاتف";
    return "وسيلة خارجية";
  }

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  // ميثود تحديث كلمة السر
  Future<void> _updatePassword() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null && user.email != null) {
        // 1. إعادة التحقق من الهوية (Re-authentication) - ضروري في Firebase لتغيير كلمة السر
        AuthCredential credential = EmailAuthProvider.credential(
          email: user.email!,
          password: _currentPasswordController.text.trim(),
        );

        await user.reauthenticateWithCredential(credential);

        // 2. تحديث كلمة السر الجديدة
        await user.updatePassword(_newPasswordController.text.trim());

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("تم تحديث كلمة السر بنجاح"), backgroundColor: Colors.teal),
          );
          Navigator.pop(context);
        }
      }
    } on FirebaseAuthException catch (e) {
      String message = "حدث خطأ أثناء التحديث";
      if (e.code == 'wrong-password') message = "كلمة السر الحالية غير صحيحة";
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ميثود نسيت كلمة السر
  Future<void> _resetPassword() async {
    final email = FirebaseAuth.instance.currentUser?.email;
    if (email != null) {
      try {
        await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("تم إرسال رابط استعادة كلمة السر لبريدك"), backgroundColor: Colors.teal),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("فشل إرسال الرابط"), backgroundColor: Colors.redAccent),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1720),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text("إدارة كلمة السر", 
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      resizeToAvoidBottomInset: false,
      body: LayoutBuilder(
        builder: (context, constraints) {
          return CustomScrollView(
            slivers: [
              SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0),
                  child: _isPasswordUser 
                  ? _buildPasswordChangeForm(constraints) 
                  : _buildSocialUserMessage(constraints),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPasswordChangeForm(BoxConstraints constraints) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: constraints.maxHeight * 0.04),
          const Text(
            "تحديث كلمة المرور",
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            "يجب أن تكون كلمة المرور قوية لحماية حسابك في Tini",
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
          SizedBox(height: constraints.maxHeight * 0.05),
          _buildPasswordField(
            label: "كلمة السر الحالية",
            controller: _currentPasswordController,
            isObscured: _isCurrentObscured,
            onToggle: () => setState(() => _isCurrentObscured = !_isCurrentObscured),
          ),
          const SizedBox(height: 20),
          _buildPasswordField(
            label: "كلمة السر الجديدة",
            controller: _newPasswordController,
            isObscured: _isNewObscured,
            onToggle: () => setState(() => _isNewObscured = !_isNewObscured),
          ),
          const SizedBox(height: 20),
          _buildPasswordField(
            label: "تأكيد كلمة السر الجديدة",
            controller: _confirmPasswordController,
            isObscured: _isConfirmObscured,
            onToggle: () => setState(() => _isConfirmObscured = !_isConfirmObscured),
            validator: (value) {
              if (value != _newPasswordController.text) {
                return "كلمات السر غير متطابقة";
              }
              return null;
            },
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _isLoading ? null : _resetPassword,
              child: const Text("نسيت كلمة السر؟", style: TextStyle(color: Color(0xFFFF3B30))),
            ),
          ),
          const Spacer(),
          Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + 20),
            child: SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal, // تم تغيير اللون إلى Teal بناءً على طلبك
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
                onPressed: _isLoading ? null : _updatePassword,
                child: _isLoading 
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text("تحديث كلمة السر", 
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSocialUserMessage(BoxConstraints constraints) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.shield_outlined, size: 80, color: Colors.teal),
        const SizedBox(height: 24),
        const Text(
          "حسابك مُؤمن",
          style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        Text(
          "أنت مسجل دخول عبر $_providerName.\nلا يتطلب حسابك كلمة مرور خاصة بـ Tini لأنك تستخدم نظام التحقق من الهوية الخاص بـ $_providerName.",
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.grey, fontSize: 15, height: 1.5),
        ),
        SizedBox(height: constraints.maxHeight * 0.1),
        Text(
          "يمكنك إدارة أمان حسابك مباشرة من إعدادات $_providerName.",
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white54, fontSize: 13),
        ),
      ],
    );
  }

  Widget _buildPasswordField({
    required String label,
    required TextEditingController controller,
    required bool isObscured,
    required VoidCallback onToggle,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 14)),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          obscureText: isObscured,
          style: const TextStyle(color: Colors.white),
          validator: validator ?? (value) => (value != null && value.length < 6) ? "الحد الأدنى 6 رموز" : null,
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFF1C1C1E),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            suffixIcon: IconButton(
              icon: Icon(isObscured ? Icons.visibility_off : Icons.visibility, color: Colors.grey),
              onPressed: onToggle,
            ),
          ),
        ),
      ],
    );
  }
}