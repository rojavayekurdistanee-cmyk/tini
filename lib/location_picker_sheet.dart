import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'tini_chat_attachments.dart';

class LocationPickerSheet extends StatefulWidget {
  const LocationPickerSheet({Key? key, this.forChat = false}) : super(key: key);
  /// الوضع القديم لإضافة الموقع للمنشورات يبقى دون تغيير.
  final bool forChat;

  @override
  _LocationPickerSheetState createState() => _LocationPickerSheetState();
}

class _LocationPickerSheetState extends State<LocationPickerSheet> {
  bool _isLoading = false;
  final MapController _mapController = MapController();
  LatLng? _selectedPoint;
  String _selectedLabel = 'الموقع المحدد';

  @override
  void initState() {
    super.initState();
    if (widget.forChat) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _locateForChat());
    }
  }

  Future<void> _locateForChat() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      final location = await TiniChatAttachments.currentLocation(context);
      if (!mounted || location == null) return;
      final point = LatLng(location.latitude, location.longitude);
      setState(() {
        _selectedPoint = point;
        _selectedLabel = location.label;
      });
      _mapController.move(point, 15);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر تحديد الموقع الحالي: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildChatMap(BuildContext context) {
    return Container(
      height: MediaQuery.sizeOf(context).height * 0.86,
      decoration: const BoxDecoration(
        color: Color(0xFF0F1720),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Column(children: [
          const SizedBox(height: 12),
          Container(width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(8))),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('اختيار موقع لإرساله',
              style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
          ),
          Expanded(child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: const LatLng(0, 0),
                initialZoom: 2,
                onTap: (_, point) => setState(() {
                  _selectedPoint = point;
                  _selectedLabel = 'الموقع المحدد';
                }),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'titi_star',
                ),
                if (_selectedPoint != null)
                  MarkerLayer(markers: [Marker(
                    point: _selectedPoint!,
                    width: 48, height: 48,
                    child: const Icon(Icons.location_pin, color: Colors.teal, size: 44),
                  )]),
                const RichAttributionWidget(attributions: [
                  TextSourceAttribution('OpenStreetMap contributors'),
                ]),
              ],
            ),
          )),
          ListTile(
            leading: const Icon(Icons.my_location, color: Colors.teal),
            title: const Text('استخدام موقعي الحالي', style: TextStyle(color: Colors.white)),
            subtitle: Text(_selectedPoint == null ? 'اضغط على الخريطة لتحديد موقع' : _selectedLabel,
              style: const TextStyle(color: Colors.white70)),
            trailing: _isLoading ? const SizedBox(width: 22, height: 22,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.teal)) : null,
            onTap: _isLoading ? null : _locateForChat,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
            child: SizedBox(width: double.infinity, child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.teal,
                foregroundColor: Colors.white, padding: const EdgeInsets.all(14)),
              onPressed: _selectedPoint == null ? null : () {
                final point = _selectedPoint!;
                Navigator.of(context).pop(TiniFixedLocation(
                  point.latitude, point.longitude, _selectedLabel));
              },
              icon: const Icon(Icons.send_outlined),
              label: const Text('إرسال الموقع المحدد'),
            )),
          ),
        ]),
      ),
    );
  }

  // قائمة افتراضية لأماكن مشهورة في حال لم يفعّل المستخدم الـ GPS
  final List<String> _suggestedLocations = ["دبي، الإمارات", "الرياض، السعودية", "القاهرة، مصر", "إسطنبول، تركيا", "الكويت"];

  Future<void> _getCurrentLocation() async {
    setState(() => _isLoading = true);
    try {
      // 1. التأكد من أن خدمة الموقع مفعلة في الجهاز
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint("Location services are disabled.");
        setState(() => _isLoading = false);
        return;
      }

      // 2. التحقق من الصلاحيات
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() => _isLoading = false);
          return;
        }
      }

      // 3. جلب الإحداثيات وتحويلها لعنوان
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high
      );
      
      List<Placemark> placemarks = await placemarkFromCoordinates(
        position.latitude, 
        position.longitude
      );

      if (placemarks.isNotEmpty) {
        Placemark place = placemarks[0];
        // تنسيق الاسم: (المدينة، الدولة)
        String locationName = "${place.locality ?? place.subAdministrativeArea}, ${place.country}";
        if (mounted) Navigator.pop(context, locationName);
      }
    } catch (e) {
      debugPrint("Location Error: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.forChat) return _buildChatMap(context);
    return Container(
      height: MediaQuery.of(context).size.height * 0.6,
      decoration: const BoxDecoration(
        color: Color(0xFF1A222C), // خلفية الحاويات المعتمدة في Tini
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          // مقبض السحب العلوي
          Container(
            width: 40, 
            height: 4, 
            decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10))
          ),
          const SizedBox(height: 10),
          const Text(
            "إضافة موقع",
            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),

          // [Tini Update]: خيار إزالة الموقع المختار (التراجع)
          ListTile(
            leading: const Icon(Icons.location_off, color: Color(0xFFE53935)), // Error Red
            title: const Text("إزالة الموقع الحالي", style: TextStyle(color: Colors.white)),
            onTap: () => Navigator.pop(context, ""), // إرجاع نص فارغ للمسح
          ),
          const Divider(color: Colors.white10, height: 1),

          ListTile(
            leading: const Icon(Icons.my_location, color: Colors.teal), // Titi Teal
            title: const Text("استخدام موقعي الحالي", style: TextStyle(color: Colors.white)),
            subtitle: const Text("تحديد الموقع عبر GPS", style: TextStyle(color: Colors.white54, fontSize: 12)),
            onTap: _getCurrentLocation,
            trailing: _isLoading 
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.teal, strokeWidth: 2)) 
                : const Icon(Icons.arrow_forward_ios, color: Colors.white24, size: 14),
          ),
          const Divider(color: Colors.white10, height: 1),
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Align(
              alignment: Alignment.centerRight,
              child: Text("أماكن مقترحة", style: TextStyle(color: Colors.white54, fontSize: 13)),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _suggestedLocations.length,
              itemBuilder: (context, index) => ListTile(
                leading: const Icon(Icons.location_on_outlined, color: Colors.white54),
                title: Text(_suggestedLocations[index], style: const TextStyle(color: Colors.white)),
                onTap: () => Navigator.pop(context, _suggestedLocations[index]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}