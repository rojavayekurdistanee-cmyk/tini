import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:iconsax/iconsax.dart';

class InAppBrowserScreen extends StatefulWidget {
  final String url;
  const InAppBrowserScreen({super.key, required this.url});

  @override
  State<InAppBrowserScreen> createState() => _InAppBrowserScreenState();
}

class _InAppBrowserScreenState extends State<InAppBrowserScreen> {
  late WebViewController controller;
  bool isLoading = true;
  String currentUrl = "";

  @override
  void initState() {
    super.initState();
    currentUrl = widget.url;
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF0F1720))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => setState(() => isLoading = true),
          onPageFinished: (_) => setState(() => isLoading = false),
          onUrlChange: (change) {
            setState(() => currentUrl = change.url ?? "");
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1720),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F1720),
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: ()=> Navigator.pop(context)),
        title: Text(currentUrl, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        actions: [
          IconButton(icon: const Icon(Iconsax.refresh, color: Colors.white70, size: 20), onPressed: ()=> controller.reload()),
        ],
        bottom: isLoading ? const PreferredSize(preferredSize: Size.fromHeight(2), child: LinearProgressIndicator(color: Colors.teal, backgroundColor: Colors.transparent)) : null,
      ),
      body: WebViewWidget(controller: controller),
    );
  }
}