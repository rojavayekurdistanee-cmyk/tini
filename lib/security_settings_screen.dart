import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'auth_provider.dart' as custom;
import 'password_management_screen.dart';

class SecuritySettingsScreen extends StatefulWidget {
  const SecuritySettingsScreen({super.key});

  @override
  State<SecuritySettingsScreen> createState() => _SecuritySettingsScreenState();
}

class _SecuritySettingsScreenState extends State<SecuritySettingsScreen> {
  final Color bgColor = const Color(0xFF0F1720);
  final Color surfaceColor = const Color(0xFF1A222C);

  bool _isOneTapEnabled = false;
  bool _isLoadingPasskey = true;
  bool _isPasskeyBusy = false;
  bool _isRepairing = false;
  String? _observedUid;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final uid = Provider.of<custom.AuthProvider>(context).uid;
    if (uid != _observedUid) {
      _observedUid = uid;
      _isOneTapEnabled = false;
      _isLoadingPasskey = uid.isNotEmpty;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadPasskeyStatus(uid);
      });
    }
  }

  Future<void> _loadPasskeyStatus(String uid) async {
    if (uid.isEmpty) {
      if (mounted && _observedUid == uid) {
        setState(() {
          _isOneTapEnabled = false;
          _isLoadingPasskey = false;
        });
      }
      return;
    }

    bool enabled = false;
    try {
      final auth = Provider.of<custom.AuthProvider>(context, listen: false);
      enabled = await auth.isPasskeyEnabledForUid(uid);
    } catch (_) {
      enabled = false;
    }

    if (!mounted ||
        _observedUid != uid ||
        FirebaseAuth.instance.currentUser?.uid != uid) {
      return;
    }
    setState(() {
      _isOneTapEnabled = enabled;
      _isLoadingPasskey = false;
    });
  }

  Future<void> _handlePasskeyToggle(
    bool requestedValue,
    custom.AuthProvider auth,
  ) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty || uid != _observedUid || _isPasskeyBusy) return;

    final previousValue = _isOneTapEnabled;
    setState(() => _isPasskeyBusy = true);
    bool succeeded = false;
    try {
      if (requestedValue) {
        succeeded = await auth.enablePasskeyForUid(uid);
      } else {
        succeeded = await auth.disablePasskeyForUid(uid);
      }
    } catch (_) {
      succeeded = false;
    }

    if (!mounted) return;
    final sameAccount = FirebaseAuth.instance.currentUser?.uid == uid &&
        _observedUid == uid;
    if (sameAccount) {
      setState(() {
        _isOneTapEnabled = succeeded ? requestedValue : previousValue;
        _isPasskeyBusy = false;
      });
    } else {
      setState(() {
        _isOneTapEnabled = false;
        _isPasskeyBusy = false;
        _isLoadingPasskey = true;
      });
    }

    if (sameAccount && !succeeded) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لم يتم تغيير حالة الدخول بلمسة واحدة. يمكنك المحاولة مرة أخرى.'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } else if (sameAccount && succeeded) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(requestedValue
              ? 'تم تفعيل الدخول بلمسة واحدة لهذا الحساب'
              : 'تم تعطيل الدخول بلمسة واحدة لهذا الحساب'),
          backgroundColor: Colors.teal,
        ),
      );
    }
  }

  Future<void> _handleVaultRepair(custom.AuthProvider auth) async {
    if (_isRepairing) return;
    setState(() => _isRepairing = true);

    try {
      final result = await auth.inspectAndRepairCurrentVault();
      final repaired = result['repaired'] == true;
      final passwordMissing = result['passwordMissing'] == true;
      final passwordStored = result['passwordStored'] == true;
      final hasPassword = result['hasPassword'] == true;

      String message;
      if (passwordMissing) {
        message = repaired
            ? 'تم إصلاح بيانات الدخول المتاحة، لكن كلمة السر غير موجودة بالخزنة ولا يمكن استعادتها تلقائياً.'
            : 'تم فحص الخزنة. كلمة السر غير موجودة فيها، ولا يمكن استعادتها تلقائياً.';
      } else if (hasPassword && passwordStored) {
        message = repaired
            ? 'تم إصلاح نوع الدخول ومعلومات الاتصال. حافظنا على كلمة السر الموجودة دون تغيير، لكن لا يمكن تأكيد صحتها دون إعادة المصادقة.'
            : 'تم فحص نوع الدخول ومعلومات الاتصال. كلمة السر الموجودة بالخزنة لم نغيّرها، ولا يمكن تأكيد صحتها دون إعادة المصادقة.';
      } else if (repaired) {
        message = 'تم إصلاح بيانات الخزنة ومزامنتها مع وسيلة الدخول الحالية.';
      } else {
        message = 'تم التحقق من بيانات الدخول ومعلومات الاتصال لهذا الحساب.';
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), backgroundColor: Colors.teal),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تعذّر إصلاح الخزنة: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isRepairing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<custom.AuthProvider>(context);
    final passkeySubtitle = _isLoadingPasskey
        ? 'جاري التحقق من حالة هذا الحساب...'
        : _isPasskeyBusy
            ? 'جاري تحديث الإعداد...'
            : _isOneTapEnabled
                ? 'الدخول السريع مفعّل لهذا الحساب'
                : 'استخدم بصمة الإصبع أو قفل شاشة الجهاز';

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new,
            color: Colors.white,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'الأمان وكلمة السر',
          style: TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Container(
              decoration: BoxDecoration(
                color: surfaceColor,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                children: [
                  _buildSecurityTile(
                    Iconsax.shield_tick,
                    'دخول بلمسة واحدة',
                    subtitle: passkeySubtitle,
                    isSwitch: true,
                    switchValue: _isOneTapEnabled,
                    switchEnabled: !_isLoadingPasskey && !_isPasskeyBusy &&
                        auth.uid.isNotEmpty,
                    onChanged: (value) => _handlePasskeyToggle(value, auth),
                  ),
                  const Divider(color: Colors.white10, height: 1),
                  _buildSecurityTile(
                    Iconsax.refresh,
                    'تحديث وتصحيح الخزنة',
                    subtitle: _isRepairing
                        ? 'جاري فحص البيانات ومزامنتها...'
                        : 'فحص بيانات الدخول وإصلاح الاختلافات الآمنة',
                    onTap: _isRepairing ? null : () => _handleVaultRepair(auth),
                    trailing: _isRepairing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.teal,
                            ),
                          )
                        : const Icon(
                            Icons.arrow_forward_ios,
                            color: Colors.white10,
                            size: 14,
                          ),
                  ),
                  const Divider(color: Colors.white10, height: 1),
                  _buildSecurityTile(
                    Iconsax.key,
                    'إدارة كلمة السر',
                    subtitle: 'تغيير كلمة السر أو ربط كلمة سر بهذا الحساب',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              const PasswordManagementScreen(),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSecurityTile(
    IconData icon,
    String title, {
    String? subtitle,
    bool isSwitch = false,
    bool switchValue = false,
    bool switchEnabled = true,
    Function(bool)? onChanged,
    VoidCallback? onTap,
    Widget? trailing,
  }) {
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: Colors.teal, size: 22),
      title: Text(
        title,
        style: const TextStyle(color: Colors.white, fontSize: 15),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            )
          : null,
      trailing: isSwitch
          ? Switch(
              value: switchValue,
              onChanged: switchEnabled ? onChanged : null,
              activeThumbColor: Colors.teal,
              activeTrackColor: Colors.teal.withValues(alpha: 0.3),
            )
          : (trailing ??
                const Icon(
                  Icons.arrow_forward_ios,
                  color: Colors.white10,
                  size: 14,
                )),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
    );
  }
}
