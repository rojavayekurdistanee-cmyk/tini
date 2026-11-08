import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'in_app_browser_screen.dart';

class OpenLinkWithSettings {
  static Future<void> open(BuildContext context, String urlText) async {
    String url = urlText;
    if (!url.startsWith('http')) url = 'https://$url';
    final uri = Uri.tryParse(url);
    if (uri == null) return;

    // حماية: إذا كان الرابط لمتجر التطبيقات، يفتح في المتصفح الخارجي إجبارياً
    if (url.contains('play.google.com') || url.contains('apps.apple.com') || url.contains('itms-apps') || url.startsWith('market://')) {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      return;
    }

    final p = await SharedPreferences.getInstance();
    bool inApp = p.getBool('browser_in_app') ?? true;
    bool warn = p.getBool('browser_warning') ?? true;

    if (warn && context.mounted) {
      bool? go = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          backgroundColor: const Color(0xFF1A222C),
          title: Text(
            inApp ? "فتح الرابط في المتصفح الداخلي؟" : "فتح الرابط في المتصفح الخارجي؟",
            style: const TextStyle(color: Colors.white, fontSize: 16)
          ),
          content: Text(url, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          actions: [
            TextButton(onPressed: ()=> Navigator.pop(c,false), child: const Text("إلغاء")),
            TextButton(onPressed: ()=> Navigator.pop(c,true), child: const Text("فتح", style: TextStyle(color: Colors.teal))),
          ],
        ),
      );
      if (go != true) return;
    }

    if (await canLaunchUrl(uri)) {
      if (inApp) {
        if (context.mounted) {
          Navigator.push(context, MaterialPageRoute(builder: (_) => InAppBrowserScreen(url: url)));
        }
      } else {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }
  }
}