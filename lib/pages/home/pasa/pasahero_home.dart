// lib/pages/home/pasahero_home.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:para2/pages/home/shared_home.dart';
import 'package:para2/pages/login/login.dart';
import 'package:para2/pages/login/qr_scan_page.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:math' as math;

class PasaheroHome extends StatefulWidget {
  const PasaheroHome({super.key});

  @override
  State<PasaheroHome> createState() => _PasaheroHomeState();
}

class _PasaheroHomeState extends State<PasaheroHome> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref("devices");

  LatLng? _destination;
  LatLng? _userLoc;
  String? _selectedJeepId;

  bool _hasSetDestination = false;
  bool _hasSelectedJeep = false;
  bool _isFollowing = true;
  bool _showHint = true;

  Map<String, Map<String, dynamic>> _jeepneys = {};
  Stream<DatabaseEvent>? _rtdbStream;
  final Set<Polyline> _polylines = {};

  @override
  void initState() {
    super.initState();
    _initUserLocation();
    _listenToJeepneys();
  }

  // ✅ Initialize GPS for passenger
  Future<void> _initUserLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("⚠️ Please enable GPS service.")),
        );
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("❌ Location permission denied.")),
        );
        return;
      }

      final pos = await Geolocator.getCurrentPosition();
      _updateUserMarker(LatLng(pos.latitude, pos.longitude));

      Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      ).listen((p) {
        _updateUserMarker(LatLng(p.latitude, p.longitude));
      });
    } catch (e) {
      debugPrint("Error initializing GPS: $e");
    }
  }

  // ✅ Update passenger marker on map + update polyline
  void _updateUserMarker(LatLng pos) {
    setState(() => _userLoc = pos);

    final shared = SharedHome.of(context);
    if (shared != null && mounted) {
      shared.addOrUpdateMarker(
        const MarkerId('user_marker'),
        Marker(
          markerId: const MarkerId('user_marker'),
          position: pos,
          infoWindow: const InfoWindow(title: 'You are here'),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueAzure,
          ),
        ),
      );
    }

    _updatePolyline();
  }

  // ✅ Listen to all jeepneys (from RTDB)
  void _listenToJeepneys() {
    _rtdbStream = _dbRef.onValue;
    _rtdbStream!.listen((event) {
      final raw = event.snapshot.value;
      if (raw == null) return;
      final Map data = (raw is Map) ? raw : {};
      final updated = <String, Map<String, dynamic>>{};

      final shared = SharedHome.of(context);
      if (shared == null) return;

      for (final entry in data.entries) {
        final id = entry.key;
        final jeep = entry.value;
        if (jeep is Map) {
          final lat = _toDouble(jeep['latitude'] ?? jeep['lat']);
          final lng = _toDouble(jeep['longitude'] ?? jeep['lng']);
          final speed = _toDouble(jeep['speed_kmh'] ?? jeep['speed']);
          final course = _toDouble(jeep['course']);

          if (lat != null && lng != null) {
            updated[id] = {
              'lat': lat,
              'lng': lng,
              'speed': speed ?? 0,
              'course': course ?? 0,
            };

            // ✅ Update jeep marker on map
            shared.addOrUpdateMarker(
              MarkerId('jeep_$id'),
              Marker(
                markerId: MarkerId('jeep_$id'),
                position: LatLng(lat, lng),
                infoWindow: InfoWindow(title: 'Jeepney $id'),
                icon: BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueYellow,
                ),
                rotation: course ?? 0,
                anchor: const Offset(0.5, 0.5),
              ),
            );
          }
        }
      }

      setState(() {
        _jeepneys = updated;
        _updatePolyline();
      });
    });
  }

  double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  // ✅ Distance and ETA helpers
  double _degToRad(double deg) => deg * math.pi / 180;
  double _distanceKm(LatLng a, LatLng b) {
    const R = 6371;
    final dLat = _degToRad(b.latitude - a.latitude);
    final dLon = _degToRad(b.longitude - a.longitude);
    final aVal =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degToRad(a.latitude)) *
            math.cos(_degToRad(b.latitude)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return R * 2 * math.atan2(math.sqrt(aVal), math.sqrt(1 - aVal));
  }

  double _computeETA(LatLng from, LatLng to, double speedKmh) {
    final dist = _distanceKm(from, to);
    if (speedKmh <= 0) return double.infinity;
    return (dist / speedKmh) * 60;
  }

  // ✅ Update lines connecting passenger, jeep, destination
  void _updatePolyline() {
    _polylines.clear();
    if (_userLoc == null) return;

    if (_hasSelectedJeep &&
        _selectedJeepId != null &&
        _jeepneys[_selectedJeepId] != null) {
      final jeep = _jeepneys[_selectedJeepId]!;
      final jeepPos = LatLng(jeep['lat'], jeep['lng']);
      _polylines.add(
        Polyline(
          polylineId: const PolylineId("trackingLine"),
          color: Colors.green,
          width: 4,
          points: [_userLoc!, jeepPos],
        ),
      );
    }

    if (_destination != null) {
      _polylines.add(
        Polyline(
          polylineId: const PolylineId("destinationLine"),
          color: Colors.blueAccent,
          width: 3,
          points: [_userLoc!, _destination!],
        ),
      );
    }

    SharedHome.of(context)?.setExternalPolylines(_polylines);
  }

  // ✅ When passenger taps map to set destination
  void _onMapTap(LatLng pos) async {
    setState(() {
      _destination = pos;
      _hasSetDestination = true;
      _showHint = false;
      _hasSelectedJeep = false;
      _selectedJeepId = null;
    });

    final destMarker = Marker(
      markerId: const MarkerId('destination_marker'),
      position: pos,
      infoWindow: const InfoWindow(title: 'Destination'),
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
    );

    final shared = SharedHome.of(context);
    shared?.addOrUpdateMarker(const MarkerId('destination_marker'), destMarker);

    final ctrl = await shared?.getMapController();
    await ctrl?.animateCamera(CameraUpdate.newLatLngZoom(pos, 16));
  }

  // ✅ Jeep list below the map
  Widget _buildJeepneySuggestionList() {
    if (!_hasSetDestination) return const SizedBox.shrink();
    if (_jeepneys.isEmpty) {
      return _buildInfoCard("No active jeepneys nearby.");
    }

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            "Available Jeepneys (Live)",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          ..._jeepneys.entries.map((entry) {
            final id = entry.key;
            final data = entry.value;
            LatLng jeepPos = LatLng(data['lat'], data['lng']);
            double? eta;
            if (_userLoc != null) {
              eta = _computeETA(jeepPos, _userLoc!, data['speed'] ?? 20);
            }

            return ListTile(
              leading: const Icon(Icons.directions_bus),
              title: Text("Jeepney $id"),
              subtitle: Text(
                eta != null && eta != double.infinity
                    ? "ETA: ${eta.toStringAsFixed(1)} min"
                    : "Speed: ${(data['speed'] ?? 0).toStringAsFixed(1)} km/h",
              ),
              trailing: _selectedJeepId == id
                  ? const Icon(Icons.check_circle, color: Colors.green)
                  : null,
              onTap: () {
                setState(() {
                  _selectedJeepId = id;
                  _hasSelectedJeep = true;
                  _updatePolyline();
                });
              },
            );
          }),
        ],
      ),
    );
  }

  Widget _buildInfoCard(String text) => Container(
    margin: const EdgeInsets.all(16),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8)],
    ),
    child: Center(child: Text(text)),
  );

  Widget _buildParaButton() {
    final isEnabled = _hasSetDestination && _hasSelectedJeep;
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 40.0),
        child: ElevatedButton(
          onPressed: isEnabled
              ? () => ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('🚍 PARA! signal sent to $_selectedJeepId'),
                  ),
                )
              : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: isEnabled
                ? Colors.greenAccent.shade700
                : Colors.grey,
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30),
            ),
          ),
          child: const Text(
            'PARA!',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildPasaheroMenu() => [
    ListTile(
      leading: const Icon(Icons.history),
      title: const Text('Trip History'),
      onTap: () {},
    ),
    ListTile(
      leading: const Icon(Icons.settings),
      title: const Text('Settings'),
      onTap: () {},
    ),
    ListTile(
      leading: const Icon(Icons.qr_code_2),
      title: const Text('Scan QR to Become Tsuperhero'),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const QRScanPage()),
        );
      },
    ),
  ];

  Future<void> _handleSignOut() async {
    await _auth.signOut();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
    );
  }

  Widget _buildRoleContent(
    BuildContext context,
    String displayName,
    LatLng? userLoc,
    void Function(LatLng)? onTap,
  ) {
    _userLoc = userLoc;
    _updatePolyline();
    return Stack(
      children: [
        if (_showHint)
          Positioned(
            top: 100,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.amber.shade700.withOpacity(0.9),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                "👆 Tap anywhere on the map to set your destination!",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        Positioned(
          bottom: 130,
          left: 0,
          right: 0,
          child: _buildJeepneySuggestionList(),
        ),
        _buildParaButton(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return SharedHome(
      roleLabel: 'PASAHERO',
      onSignOut: _handleSignOut,
      roleMenu: _buildPasaheroMenu(),
      roleContentBuilder: _buildRoleContent,
      onMapTap: _onMapTap,
    );
  }
}
