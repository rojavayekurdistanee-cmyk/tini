import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'auth_provider.dart' as custom;

const Color kBg = Color(0xFF0F1720);
const Color kTeal = Colors.teal;

class ReadReceiptsScreen extends StatelessWidget {
  const ReadReceiptsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<custom.AuthProvider>();
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kBg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'عرض مؤشرات قراءة الرسائل',
          style: TextStyle(
            color: Colors.white,
            fontFamily: 'Tajawal',
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'مؤشرات قراءة الرسائل',
                    style: TextStyle(
                      color: Colors.white,
                      fontFamily: 'Tajawal',
                      fontSize: 15,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'يمكن للآخرين معرفة أنك قرأت رسائلهم.',
                    style: TextStyle(
                      color: Colors.white54,
                      fontFamily: 'Tajawal',
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: auth.showReadReceipts,
              thumbColor: const WidgetStatePropertyAll(Colors.white),
              trackColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return kTeal;
                }
                return Colors.white24;
              }),
              onChanged: (v) => auth.updateReadReceipts(v),
            ),
          ],
        ),
      ),
    );
  }
}