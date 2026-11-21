import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'auth_provider.dart' as custom;

class PasswordManagementScreen extends StatefulWidget {
  const PasswordManagementScreen({Key? key}) : super(key: key);

  @override
  State<PasswordManagementScreen> createState() =>
      _PasswordManagementScreenState();
}

class _PasswordManagementScreenState extends State<PasswordManagementScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _currentPasswordController =
      TextEditingController();
  final TextEditingController _newPasswordController =
      TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  bool _isCurrentObscured = true;
  bool _isNewObscured = true;
  bool _isConfirmObscured = true;
  bool _isLoading = false;
  bool _hasPasswordProvider = false;
  String _providerName = 'وسيلة الدخول الحالية';
  String? _accountUid;

  @override
  void initState() {
    super.initState();
    _loadAccountProviders();
  }

  void _loadAccountProviders() {
    final user = FirebaseAuth.instance.currentUser;
    _accountUid = user?.uid;
    if (user == null) {
      _hasPasswordProvider = false;
      _providerName = 'غير معروف';
      return;
    }
    final providers = user.providerData.map((info) => info.providerId).toSet();
    _hasPasswordProvider = providers.contains('password');

    if (providers.contains('google.com')) {
      _providerName = 'Google';
    } else if (providers.contains('phone')) {
      _providerName = 'رقم الهاتف';
    } else if (_hasPasswordProvider) {
      _providerName = 'البريد الإلكتروني وكلمة السر';
    } else {
      _providerName = 'وسيلة خارجية';
    }

    if ((user.email ?? '').isNotEmpty) {
      _emailController.text = user.email!;
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  String _firebaseErrorMessage(FirebaseAuthException error) {
    switch (error.code) {
      case 'wrong-password':
      case 'invalid-credential':
      case 'user-mismatch':
      case 'user-not-found':
        return 'كلمة السر الحالية غير صحيحة. تأكد منها وحاول مرة ثانية.';
      case 'requires-recent-login':
      case 'user-token-expired':
        return 'انتهت صلاحية جلسة الدخول. سجّل دخولك من جديد ثم أعد المحاولة.';
      case 'weak-password':
        return 'كلمة السر الجديدة ضعيفة. استخدم 6 رموز على الأقل.';
      case 'email-already-in-use':
      case 'credential-already-in-use':
        return 'هذا البريد مرتبط بحساب آخر، لذلك ما قدرنا نربطه بهذا الحساب.';
      case 'provider-already-linked':
        return 'كلمة السر مرتبطة بهذا الحساب بالفعل.';
      case 'network-request-failed':
        return 'تعذر الاتصال بالإنترنت. تحقق من الاتصال وحاول مرة ثانية.';
      case 'too-many-requests':
        return 'تمت محاولات كثيرة. انتظر قليلاً ثم حاول مرة ثانية.';
      case 'user-disabled':
        return 'هذا الحساب موقوف حالياً.';
      default:
        return 'حدث خطأ أثناء تنفيذ العملية: ${error.message ?? error.code}';
    }
  }

  Future<void> _updatePassword() async {
    if (!_formKey.currentState!.validate()) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.uid != _accountUid) {
      _showMessage('انتهت جلسة الدخول. سجّل دخولك من جديد.', isError: true);
      return;
    }

    setState(() => _isLoading = true);
    final newPassword = _newPasswordController.text;
    final auth = Provider.of<custom.AuthProvider>(context, listen: false);
    bool firebaseUpdated = false;

    try {
      final email = user.email;
      if (email == null || email.isEmpty) {
        throw FirebaseAuthException(
          code: 'invalid-credential',
          message: 'لا يوجد بريد مرتبط بمزوّد كلمة السر.',
        );
      }

      final credential = EmailAuthProvider.credential(
        email: email,
        password: _currentPasswordController.text,
      );
      await user.reauthenticateWithCredential(credential);

      if (FirebaseAuth.instance.currentUser?.uid != user.uid) {
        throw StateError('تغير الحساب أثناء إعادة المصادقة');
      }
      await user.updatePassword(newPassword);
      firebaseUpdated = true;

      try {
        await auth.savePasswordToVaultStrict(user.uid, newPassword);
      } catch (_) {
        // لا نترك كلمة السر القديمة في الخزنة إن أمكن حذفها.
        try {
          await auth.clearPasswordFromVaultStrict(user.uid);
        } catch (_) {}
        if (mounted) {
          _showMessage(
            'تم تغيير كلمة السر في Firebase، لكن تعذرت مزامنتها مع الخزنة المحلية. استخدم زر «تحديث وتصحيح الخزنة» لمعالجة البيانات المحلية.',
            isError: true,
          );
        }
        return;
      }

      if (mounted) {
        _showMessage('تم تحديث كلمة السر ومزامنتها مع الخزنة بنجاح.');
        Navigator.pop(context);
      }
    } on FirebaseAuthException catch (error) {
      if (mounted) _showMessage(_firebaseErrorMessage(error), isError: true);
    } catch (error) {
      if (mounted) {
        _showMessage(
          firebaseUpdated
              ? 'تم تغيير كلمة السر، لكن تعذرت معالجة بقية البيانات المحلية.'
              : 'تعذر إكمال العملية: $error',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _linkPassword() async {
    if (!_formKey.currentState!.validate()) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.uid != _accountUid) {
      _showMessage('انتهت جلسة الدخول. سجّل دخولك من جديد.', isError: true);
      return;
    }

    final email = (user.email ?? _emailController.text).trim();
    if (email.isEmpty) {
      _showMessage('أدخل بريداً إلكترونياً لربط كلمة السر بالحساب.', isError: true);
      return;
    }

    setState(() => _isLoading = true);
    final auth = Provider.of<custom.AuthProvider>(context, listen: false);
    bool linked = false;

    try {
      final credential = EmailAuthProvider.credential(
        email: email,
        password: _newPasswordController.text,
      );
      final result = await user.linkWithCredential(credential);
      linked = result.user != null;

      if (!linked || FirebaseAuth.instance.currentUser?.uid != user.uid) {
        throw StateError('لم يتم تأكيد ربط كلمة السر بالحساب الحالي');
      }

      await auth.savePasswordToVaultStrict(user.uid, _newPasswordController.text);
      try {
        await auth.syncAccountProvidersFromFirebase();
      } catch (_) {
        if (mounted) {
          _showMessage(
            'تم ربط كلمة السر بالحساب، لكن تعذرت مزامنة بعض بيانات الخزنة. استخدم زر «تحديث وتصحيح الخزنة» من إعدادات الأمان.',
            isError: true,
          );
        }
        return;
      }

      if (mounted) {
        _showMessage('تم ربط كلمة السر بحسابك وحفظها في الخزنة.');
        Navigator.pop(context);
      }
    } on FirebaseAuthException catch (error) {
      if (mounted) _showMessage(_firebaseErrorMessage(error), isError: true);
    } catch (error) {
      if (mounted) {
        _showMessage(
          linked
              ? 'تم ربط كلمة السر، لكن تعذر حفظها محلياً. افتح إصلاح الخزنة لمعالجة المزامنة.'
              : 'تعذر ربط كلمة السر: $error',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resetPassword() async {
    final email = FirebaseAuth.instance.currentUser?.email;
    if (email == null || email.isEmpty) {
      _showMessage('ما في بريد إلكتروني مرتبط بهذا الحساب.', isError: true);
      return;
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (mounted) _showMessage('تم إرسال رابط استعادة كلمة السر إلى بريدك.');
    } on FirebaseAuthException catch (error) {
      if (mounted) _showMessage(_firebaseErrorMessage(error), isError: true);
    } catch (_) {
      if (mounted) _showMessage('فشل إرسال رابط الاستعادة.', isError: true);
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.redAccent : Colors.teal,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Scaffold(
        backgroundColor: const Color(0xFF0F1720),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: const Text('إدارة كلمة السر',
              style: TextStyle(color: Colors.white)),
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: const Center(
          child: Text('سجّل دخولك أولاً.', style: TextStyle(color: Colors.white70)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0F1720),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'إدارة كلمة السر',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      resizeToAvoidBottomInset: true,
      body: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight - 24),
              child: _hasPasswordProvider
                  ? _buildPasswordChangeForm(constraints)
                  : _buildPasswordLinkForm(constraints),
            ),
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
          SizedBox(height: constraints.maxHeight * 0.03),
          const Text(
            'تحديث كلمة السر',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'أدخل كلمة السر الحالية ثم اختر كلمة سر جديدة لحماية حسابك في Tini.',
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
          SizedBox(height: constraints.maxHeight * 0.04),
          _buildPasswordField(
            label: 'كلمة السر الحالية',
            controller: _currentPasswordController,
            isObscured: _isCurrentObscured,
            onToggle: () => setState(() => _isCurrentObscured = !_isCurrentObscured),
            validator: (value) => (value == null || value.isEmpty)
                ? 'أدخل كلمة السر الحالية'
                : null,
          ),
          const SizedBox(height: 20),
          _buildNewPasswordFields(),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _isLoading ? null : _resetPassword,
              child: const Text('نسيت كلمة السر؟',
                  style: TextStyle(color: Color(0xFFFF3B30))),
            ),
          ),
          const SizedBox(height: 24),
          _buildActionButton('تحديث كلمة السر', _updatePassword),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildPasswordLinkForm(BoxConstraints constraints) {
    final needsEmail = (FirebaseAuth.instance.currentUser?.email ?? '').isEmpty;
    return Form(
      key: _formKey,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: constraints.maxHeight * 0.08),
          const Center(child: Icon(Icons.shield_outlined, size: 72, color: Colors.teal)),
          const SizedBox(height: 22),
          const Center(
            child: Text(
              'إضافة كلمة سر للحساب',
              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'حسابك مسجل عبر $_providerName ولا يحتوي حالياً على كلمة سر خاصة بالبريد. يمكنك ربط كلمة سر بحسابك الحالي دون إنشاء حساب جديد.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey, fontSize: 14, height: 1.5),
          ),
          const SizedBox(height: 28),
          if (needsEmail) ...[
            const Text('البريد الإلكتروني',
                style: TextStyle(color: Colors.white70, fontSize: 14)),
            const SizedBox(height: 8),
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              style: const TextStyle(color: Colors.white),
              validator: (value) {
                final email = value?.trim() ?? '';
                if (email.isEmpty || !email.contains('@')) {
                  return 'أدخل بريداً إلكترونياً صحيحاً';
                }
                return null;
              },
              decoration: _inputDecoration(),
            ),
            const SizedBox(height: 20),
          ],
          _buildNewPasswordFields(),
          const SizedBox(height: 28),
          _buildActionButton('ربط كلمة السر بالحساب', _linkPassword),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildNewPasswordFields() {
    return Column(
      children: [
        _buildPasswordField(
          label: 'كلمة السر الجديدة',
          controller: _newPasswordController,
          isObscured: _isNewObscured,
          onToggle: () => setState(() => _isNewObscured = !_isNewObscured),
        ),
        const SizedBox(height: 20),
        _buildPasswordField(
          label: 'تأكيد كلمة السر الجديدة',
          controller: _confirmPasswordController,
          isObscured: _isConfirmObscured,
          onToggle: () => setState(() => _isConfirmObscured = !_isConfirmObscured),
          validator: (value) {
            if (value != _newPasswordController.text) {
              return 'كلمتا السر غير متطابقتين';
            }
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildActionButton(String label, VoidCallback action) {
    return SizedBox(
      width: double.infinity,
      height: 55,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.teal,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        ),
        onPressed: _isLoading ? null : action,
        child: _isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
              )
            : Text(
                label,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              ),
      ),
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
          validator: validator ??
              (value) => (value == null || value.length < 6)
                  ? 'الحد الأدنى 6 رموز'
                  : null,
          decoration: _inputDecoration(
            suffixIcon: IconButton(
              icon: Icon(
                isObscured ? Icons.visibility_off : Icons.visibility,
                color: Colors.grey,
              ),
              onPressed: onToggle,
            ),
          ),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration({Widget? suffixIcon}) {
    return InputDecoration(
      filled: true,
      fillColor: const Color(0xFF1C1C1E),
      suffixIcon: suffixIcon,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    );
  }
}
