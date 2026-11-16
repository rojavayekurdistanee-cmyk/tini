import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_colors.dart';
import 'crown_provider.dart';
import 'galaxy_screen.dart';
import 'tini_throne_fullscreen.dart';

class CommunityHubScreen extends StatelessWidget {
  const CommunityHubScreen({super.key});

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (_) => CrownProvider(),
    child: GestureDetector(
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      child: const Scaffold(
        resizeToAvoidBottomInset: false,
        backgroundColor: AppColors.background,
        body: SafeArea(child: _CommunityHubSections()),
      ),
    ),
  );
}

class _CommunityHubSections extends StatefulWidget {
  const _CommunityHubSections();

  @override
  State<_CommunityHubSections> createState() => _CommunityHubSectionsState();
}

class _CommunityHubSectionsState extends State<_CommunityHubSections> {
  int _section = 0;
  bool _galaxyOpened = false;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          textDirection: TextDirection.rtl,
          children: [
            _sectionButton(0, 'العرش', Icons.workspace_premium_outlined),
            const SizedBox(width: 12),
            _sectionButton(1, 'المجرة', Icons.auto_awesome_outlined),
          ],
        ),
      ),
      Expanded(
        child: IndexedStack(
          index: _section,
          children: [
            TickerMode(
              enabled: _section == 0,
              child: const TiniThroneFullScreen(),
            ),
            if (_galaxyOpened)
              GalaxyScreen(active: _section == 1)
            else
              const SizedBox.expand(),
          ],
        ),
      ),
    ],
  );

  Widget _sectionButton(int index, String label, IconData icon) {
    final selected = _section == index;
    return Expanded(
      child: Semantics(
        selected: selected,
        child: TextButton.icon(
          onPressed: () {
            FocusManager.instance.primaryFocus?.unfocus();
            setState(() {
              _section = index;
              if (index == 1) _galaxyOpened = true;
            });
          },
          style: TextButton.styleFrom(
            foregroundColor: selected
                ? const Color(0xFF80CBC4)
                : Colors.white60,
            backgroundColor: selected
                ? const Color(0xFF163A40)
                : Colors.transparent,
            minimumSize: const Size(0, 44),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          icon: Icon(icon, size: 20),
          label: Text(label),
        ),
      ),
    );
  }
}
