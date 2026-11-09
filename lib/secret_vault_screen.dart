import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app_colors.dart';
import 'crown_provider.dart';
import 'box_provider.dart';
import 'tini_throne_fullscreen.dart';
import 'mystery_sea_grid.dart';

class SecretVaultScreen extends StatefulWidget {
  const SecretVaultScreen({super.key});

  @override
  State<SecretVaultScreen> createState() => _SecretVaultScreenState();
}

class _SecretVaultScreenState extends State<SecretVaultScreen> {
  bool _hideBidField = false;

  void _setHideBidField(bool hide) {
    if (!mounted || _hideBidField == hide) return;
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
      child: DefaultTabController(
        length: 2,
        initialIndex: 0, // فتح العرش تلقائياً عند دخول تبويب «السر»
        child: GestureDetector(
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          child: Scaffold(
            resizeToAvoidBottomInset: false, // ← منع الكيبورد من تحريك العرش
            backgroundColor: AppColors.background,
            body: SafeArea(
              child: Column(
                children: [
                  // التبويبان مستقلان؛ كل قسم يأخذ كامل المساحة المتاحة أسفلهما.
                  Material(
                    color: AppColors.surface,
                    child: TabBar(
                      isScrollable: false,
                      indicatorSize: TabBarIndicatorSize.tab,
                      indicatorColor: AppColors.primary,
                      indicatorWeight: 3,
                      labelColor: AppColors.textPrimary,
                      unselectedLabelColor: AppColors.greyText,
                      labelStyle: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                      unselectedLabelStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                      tabs: const [
                        Tab(icon: Icon(Icons.emoji_events_outlined, size: 22), text: 'العرش'),
                        Tab(icon: Icon(Icons.inventory_2_outlined, size: 22), text: 'بحر الصناديق'),
                      ],
                    ),
                  ),
                  // 1. العرش - شاشة كاملة ديناميكية ومستقلة عن بحر الصناديق.
                  // 2. بحر الصناديق - شبكة مستقلة مع الاحتفاظ بالفلترة والحجز والفتح.
                  Expanded(
                    child: TabBarView(
                      children: [
                        _VaultKeepAlive(
                          child: TiniThroneFullScreen(hideBidField: _hideBidField),
                        ),
                        _VaultKeepAlive(
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              return Center(
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth: constraints.maxWidth > 940 ? 940 : constraints.maxWidth,
                                    maxHeight: constraints.maxHeight,
                                  ),
                                  child: MysterySeaGrid(
                                    onModalOpen: _setHideBidField,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// لا نفقد حالة الفلتر أو موضع التمرير عند الانتقال بين التبويبين.
class _VaultKeepAlive extends StatefulWidget {
  final Widget child;
  const _VaultKeepAlive({required this.child});

  @override
  State<_VaultKeepAlive> createState() => _VaultKeepAliveState();
}

class _VaultKeepAliveState extends State<_VaultKeepAlive>
    with AutomaticKeepAliveClientMixin<_VaultKeepAlive> {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
