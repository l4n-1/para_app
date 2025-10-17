import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:para2/pages/login/login.dart';
import 'package:para2/pages/home/shared_home.dart';
import 'package:para2/services/RealtimeDatabaseService.dart';

class TsuperheroHome extends StatefulWidget {
  const TsuperheroHome({super.key});

  @override
  State<TsuperheroHome> createState() => _TsuperheroHomeState();
}

class _TsuperheroHomeState extends State<TsuperheroHome> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final RealtimeDatabaseService _rtdbService = RealtimeDatabaseService();

  StreamSubscription<DatabaseEvent>? _trackerSub;
  Marker? _jeepMarker;
  bool _hasCentered = false;

  String _plateNumber = 'DRVR-XXX';
  bool _isOnline = false;
  String? _trackerId;

  @override
  void initState() {
    super.initState();
    _initDriverData();
  }

  Future<void> _initDriverData() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final doc = await _firestore.collection('users').doc(user.uid).get();
      if (!doc.exists) return;

      final data = doc.data() ?? {};
      _plateNumber = data['plateNumber'] ?? 'DRVR-XXX';
      final boxId = data['boxClaimed'];

      if (boxId != null) {
        final boxDoc = await _firestore
            .collection('baryaBoxes')
            .doc(boxId)
            .get();
        if (boxDoc.exists) {
          _trackerId = boxDoc.data()?['trackerId'];
        }
      }

      if (_trackerId != null) {
        _listenToTracker(_trackerId!);
      }

      setState(() {});
    } catch (e) {
      debugPrint('Error initializing driver data: $e');
    }
  }

  void _listenToTracker(String trackerId) {
    _trackerSub?.cancel();

    final trackerRef = _rtdbService.database.ref('devices/$trackerId');
    debugPrint("📡 Listening to tracker path: devices/$trackerId");

    _trackerSub = trackerRef.onValue.listen((event) async {
      final snapshot = event.snapshot;
      if (!snapshot.exists || snapshot.value == null) return;

      final raw = snapshot.value;
      if (raw is! Map) return;

      final data = raw.cast<String, dynamic>();
      final lat = double.tryParse(
        data['latitude']?.toString() ?? data['lat']?.toString() ?? '',
      );
      final lng = double.tryParse(
        data['longitude']?.toString() ?? data['lng']?.toString() ?? '',
      );
      final speed = double.tryParse(
        data['speed_kmh']?.toString() ?? data['speed']?.toString() ?? '0',
      );

      if (lat == null || lng == null) {
        debugPrint("⚠️ Invalid lat/lng for tracker $trackerId: $data");
        return;
      }

      final pos = LatLng(lat, lng);

      final marker = Marker(
        markerId: const MarkerId('tsuperhero_jeep'),
        position: pos,
        infoWindow: InfoWindow(
          title: _plateNumber,
          snippet: 'Speed: ${(speed ?? 0).toStringAsFixed(1)} km/h',
        ),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
      );

      setState(() => _jeepMarker = marker);

      // ✅ Update SharedHome map in real time
      final sharedHome = SharedHome.of(context);
      if (sharedHome != null) {
        sharedHome.addOrUpdateMarker(const MarkerId('tsuperhero_jeep'), marker);
        if (!_hasCentered) {
          await sharedHome.centerMap(pos);
          _hasCentered = true;
        }
      }

      debugPrint("📍 Jeep updated: ($lat, $lng)");
    });
  }

  Future<void> _handleSignOut() async {
    await _auth.signOut();
    await _trackerSub?.cancel();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
    );
  }

  void _toggleOnlineStatus() async {
    setState(() => _isOnline = !_isOnline);
    try {
      final user = _auth.currentUser;
      if (user != null) {
        await _firestore.collection('users').doc(user.uid).update({
          'isOnline': _isOnline,
          'lastStatusChange': FieldValue.serverTimestamp(),
        });
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isOnline ? '🟢 You are now ONLINE' : '🔴 You are now OFFLINE',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      debugPrint('Error updating online status: $e');
    }
  }

  @override
  void dispose() {
    _trackerSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SharedHome(
      roleLabel: 'TSUPERHERO',
      onSignOut: _handleSignOut,
      roleMenu: _buildDriverMenu(),
      // ✅ Use new builder parameter for content
      roleContentBuilder: (context, role, userLoc, onMapTap) =>
          _buildDriverContent(),
    );
  }

  Widget _buildDriverContent() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (_jeepMarker != null)
          Text(
            "Jeep Position:\n${_jeepMarker!.position.latitude.toStringAsFixed(6)}, "
            "${_jeepMarker!.position.longitude.toStringAsFixed(6)}",
            textAlign: TextAlign.center,
          )
        else if (_trackerId != null)
          const Text("Waiting for tracker GPS data...")
        else
          const Text("No tracker linked. Scan QR to activate your BaryaBox."),
        const SizedBox(height: 15),
        ElevatedButton.icon(
          onPressed: _toggleOnlineStatus,
          style: ElevatedButton.styleFrom(
            backgroundColor: _isOnline ? Colors.red : Colors.green,
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
          ),
          icon: Icon(_isOnline ? Icons.power_settings_new : Icons.play_arrow),
          label: Text(_isOnline ? 'Go Offline' : 'Go Online'),
        ),
        const SizedBox(height: 15),
        if (_jeepMarker != null)
          ElevatedButton(
            onPressed: () async {
              final sharedHome = SharedHome.of(context);
              if (sharedHome != null) {
                await sharedHome.centerMap(_jeepMarker!.position);
              }
            },
            child: const Text("Center Map on My Jeep"),
          ),
      ],
    );
  }

  List<Widget> _buildDriverMenu() {
    return [
      ListTile(
        leading: const Icon(Icons.qr_code_scanner),
        title: const Text('Scan Activation QR'),
        onTap: () {},
      ),
      ListTile(
        leading: const Icon(Icons.route),
        title: const Text('Assigned Route'),
        onTap: () {},
      ),
      ListTile(
        leading: const Icon(Icons.person),
        title: const Text('Profile Settings'),
        onTap: () {},
      ),
      ListTile(
        leading: const Icon(Icons.settings),
        title: const Text('App Settings'),
        onTap: () {},
      ),
    ];
  }
}
