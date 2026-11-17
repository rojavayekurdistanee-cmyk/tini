import 'package:flutter/material.dart';
import 'galaxy_match_service.dart';
import 'galaxy_match_provider.dart';
import 'galaxy_match_setup_screen.dart';
import 'galaxy_match_discover_screen.dart';
import 'galaxy_match_inbox_screen.dart';

class GalaxyMatchEntrySheet extends StatefulWidget {
  final GalaxyMatchBackend? backend;
  final GalaxyMatchProvider? badgeProvider;
  const GalaxyMatchEntrySheet({super.key, this.backend, this.badgeProvider});
  @override
  State<GalaxyMatchEntrySheet> createState() => _GalaxyMatchEntrySheetState();
}

class _GalaxyMatchEntrySheetState extends State<GalaxyMatchEntrySheet> {
  late final GalaxyMatchProvider _provider;
  @override
  void initState() {
    super.initState();
    _provider = GalaxyMatchProvider(widget.backend ?? GalaxyMatchService());
  }

  @override
  void dispose() {
    _provider.dispose();
    super.dispose();
  }

  Future<void> _discover() async {
    if (_provider.preferences?.enabled != true) {
      await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => GalaxyMatchSetupScreen(provider: _provider),
        ),
      );
    }
    if (!mounted ||
        !_provider.signedIn ||
        _provider.preferences?.enabled != true) {
      return;
    }
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => GalaxyMatchDiscoverScreen(provider: _provider),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([_provider, ?widget.badgeProvider]),
    builder: (context, _) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'النجمة الناقصة',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'اكتشف من يكملك بتبادل المهارات',
              style: TextStyle(color: Colors.white70),
            ),
            if (!_provider.signedIn)
              const Text(
                'سجّل الدخول لاستخدام الميزة',
                style: TextStyle(color: Colors.white70),
              )
            else if (!_provider.ready)
              const Padding(
                padding: EdgeInsets.all(12),
                child: CircularProgressIndicator(),
              ),
            if (_provider.error != null)
              Text(
                _provider.error!,
                style: const TextStyle(color: Colors.redAccent),
              ),
            ListTile(
              leading: const Icon(Icons.auto_awesome, color: Colors.teal),
              title: const Text(
                'اكتشف من يكملك',
                style: TextStyle(color: Colors.white),
              ),
              onTap: _provider.ready ? _discover : null,
            ),
            ListTile(
              leading: Badge(
                isLabelVisible:
                    widget.badgeProvider?.hasIncomingRequests ??
                    _provider.hasIncomingRequests,
                backgroundColor: Colors.redAccent,
                child: const Icon(Icons.inbox_outlined, color: Colors.teal),
              ),
              subtitle:
                  (widget.badgeProvider?.hasIncomingRequests ??
                      _provider.hasIncomingRequests)
                  ? const Text(
                      'لديك طلبات واردة بانتظار الرد',
                      style: TextStyle(color: Colors.white60),
                    )
                  : null,
              title: const Text(
                'توافقاتي',
                style: TextStyle(color: Colors.white),
              ),
              onTap: !_provider.signedIn
                  ? null
                  : () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            GalaxyMatchInboxScreen(provider: _provider),
                      ),
                    ),
            ),
            ListTile(
              leading: const Icon(Icons.tune, color: Colors.teal),
              title: const Text(
                'تعديل اختياراتي',
                style: TextStyle(color: Colors.white),
              ),
              onTap: !_provider.ready
                  ? null
                  : () => Navigator.push(
                      context,
                      MaterialPageRoute<bool>(
                        builder: (_) =>
                            GalaxyMatchSetupScreen(provider: _provider),
                      ),
                    ),
            ),
          ],
        ),
      ),
    ),
  );
}