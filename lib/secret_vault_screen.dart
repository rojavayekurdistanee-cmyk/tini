import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app_colors.dart';
import 'crown_provider.dart';
import 'box_provider.dart';
import 'throne_section.dart';
import 'mystery_sea_grid.dart';

class SecretVaultScreen extends StatefulWidget {
  const SecretVaultScreen({super.key});

  @override
  State<SecretVaultScreen> createState() => _SecretVaultScreenState();
}

class _SecretVaultScreenState extends State<SecretVaultScreen> {
  bool _hideBidField = false;

  void _setHideBidField(bool hide) {
    setState(() {
      _hideBidField = hide;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => CrownProvider()),
        ChangeNotifierProvider(create: (_) => BoxProvider()),
      ],
      child: GestureDetector(
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: Scaffold(
          resizeToAvoidBottomInset: false, // ← منع الكيبورد من تحريك العرش
          backgroundColor: AppColors.background,
          body: SafeArea(
            child: Column(
              children: [
                // 1. العرش - ثابت بياخذ حجمه الطبيعي
                ThroneSection(hideBidField: _hideBidField),
                
                // 2. خط فاصل رفيع
                Container(
                  height: 0.5,
                  color: AppColors.primary.withValues(alpha: 0.2),
                ),

                // 3. بحر الصناديق - بياخذ باقي الشاشة وسكروله الوحيد شغال
                Expanded(
                  child: MysterySeaGrid(
                    onModalOpen: _setHideBidField,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}