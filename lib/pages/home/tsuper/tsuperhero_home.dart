// lib/pages/tsuper/tsuperhero_home.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:para2/pages/login/login.dart';
import 'package:para2/pages/home/shared_home.dart';
import 'package:para2/services/RealtimeDatabaseService.dart'; // ✅ Correct import (lowercase file name)

class TsuperheroHome extends StatefulWidget {
  const TsuperheroHome({super.key});

  @override
  State<TsuperheroHome> createState() => _TsuperheroHomeState();
}

class _TsuperheroHomeState extends State<TsuperheroHome> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final RealtimeDatabaseService _rtdbService =
      RealtimeDatabaseService(); // ✅ Centralized RTDB service

  StreamSubscription<DatabaseEvent>? _trackerSub;
  Marker? _jeepMarker;

  String _plateNumber = 'DRVR-XXX';
  bool _isOnline = false;
  String? _TrackerId;

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
      final plate = data['plateNumber'] ?? 'DRVR-XXX';
      final boxId = data['boxClaimed'];
      String? trackerId;

      // Check if user has a claimed box
      if (boxId != null) {
        final boxDoc = await _firestore
            .collection('baryaBoxes')
            .doc(boxId)
            .get();
        if (boxDoc.exists) {
          trackerId = boxDoc.data()?['trackerId'];
        }
      }

      setState(() {
        _plateNumber = plate;
        _TrackerId = trackerId;
      });

      if (trackerId != null) {
        _listenToTracker(trackerId);
      }
    } catch (e) {
      debugPrint('Error initializing driver data: $e');
    }
  }

  void _listenToTracker(String trackerId) {
    _trackerSub?.cancel();

    // ✅ Listen directly under devices/<trackerId>
    final trackerRef = _rtdbService.database.ref('devices/$trackerId');
    debugPrint("Listening to tracker at path: devices/$trackerId");

    _trackerSub = trackerRef.onValue.listen(
      (event) {
        final snapshot = event.snapshot;
        debugPrint("📡 Raw snapshot: ${snapshot.value}");

        if (!snapshot.exists || snapshot.value == null) {
          debugPrint(
            "⚠️ Tracker node devices/$trackerId not found or empty in RTDB",
          );
          return;
        }

        // Convert snapshot to map
        Map<String, dynamic> data = {};
        try {
          final raw = snapshot.value;
          if (raw is Map) {
            raw.forEach((k, v) {
              data[k.toString()] = v;
            });
          } else {
            debugPrint("⚠️ Unexpected RTDB payload type: ${raw.runtimeType}");
          }
        } catch (e) {
          debugPrint("⚠️ Error converting snapshot to map: $e");
          return;
        }

        debugPrint("📡 Tracker data keys: ${data.keys.toList()}");

        final latRaw = data['latitude'] ?? data['lat'];
        final lngRaw = data['longitude'] ?? data['lng'];
        final speed = data['speed_kmh'] ?? data['speed'] ?? 0;

        if (latRaw == null || lngRaw == null) {
          debugPrint("⚠️ Missing latitude/longitude in tracker data");
          return;
        }

        double? parseDouble(dynamic v) {
          if (v is num) return v.toDouble();
          if (v is String) return double.tryParse(v);
          return null;
        }

        final lat = parseDouble(latRaw);
        final lng = parseDouble(lngRaw);
        if (lat == null || lng == null) {
          debugPrint(
            "⚠️ Could not parse lat/lng to double. latRaw=$latRaw lngRaw=$lngRaw",
          );
          return;
        }

        final pos = LatLng(lat, lng);

        setState(() {
          _jeepMarker = Marker(
            markerId: const MarkerId('tsuperhero_jeep'),
            position: pos,
            infoWindow: InfoWindow(
              title: trackerId,
              snippet: 'Speed: ${speed.toString()} km/h',
            ),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueAzure,
            ),
          );
        });

        // 🗺️ Update marker on shared map
        final sharedHome = SharedHome.of(context);
        sharedHome?.updateJeepMarker(_jeepMarker!);
      },
      onError: (err) {
        debugPrint("RTDB listener error: $err");
      },
    );
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
      roleContent: _buildDriverContent(),
      roleMenu: _buildDriverMenu(),
    );
  }

  Widget _buildDriverContent() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (_jeepMarker != null)
          Text(
            "Live Position: ${_jeepMarker!.position.latitude.toStringAsFixed(6)}, "
            "${_jeepMarker!.position.longitude.toStringAsFixed(6)}",
            style: const TextStyle(fontSize: 16),
          )
        else if (_TrackerId != null)
          const Text("Waiting for GPS data...")
        else
          const Text("No tracker linked. Scan QR to activate your BaryaBox."),
        const SizedBox(height: 20),
        ElevatedButton.icon(
          onPressed: _toggleOnlineStatus,
          style: ElevatedButton.styleFrom(
            backgroundColor: _isOnline
                ? Colors.redAccent
                : const Color.fromARGB(255, 73, 172, 123),
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30),
            ),
          ),
          icon: Icon(
            _isOnline ? Icons.power_settings_new : Icons.play_arrow,
            color: Colors.white,
          ),
          label: Text(
            _isOnline ? 'Go Offline' : 'Go Online',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 20),
        if (_jeepMarker != null)
          ElevatedButton(
            onPressed: () {
              final sharedHome = SharedHome.of(context);
              if (_jeepMarker != null && sharedHome != null) {
                sharedHome.centerMap(_jeepMarker!.position);
              }
            },
            child: const Text("Center Map on Jeep"),
          ),
      ],
    );
  }

  List<Widget> _buildDriverMenu() {
    return [
      ListTile(
        leading: const Icon(Icons.qr_code_scanner),
        title: const Text('Scan Activation QR'),
        onTap: () {
          // TODO: navigate to QR activation page
        },
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
