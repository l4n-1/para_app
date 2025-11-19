// lib/pages/home/pasahero_home.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:para2/pages/home/shared_home.dart';
import 'package:para2/pages/login/login.dart';
import 'package:para2/pages/login/qr_scan_page.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:math' as math;
import 'package:para2/theme/app_icons.dart';
import 'package:para2/pages/settings/profile_settings.dart';
import 'package:para2/services/RealtimeDatabaseService.dart';
import 'package:para2/services/button_actions.dart';
import 'package:para2/widgets/compact_ads_button.dart';
import 'package:para2/pages/biyahe/biyahe_logs_page.dart';

class PasaheroHome extends StatefulWidget {
  const PasaheroHome({super.key});

  @override
  State<PasaheroHome> createState() => _PasaheroHomeState();
}

class _PasaheroHomeState extends State<PasaheroHome> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final RealtimeDatabaseService _rtdbService = RealtimeDatabaseService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  LatLng? _destination;
  LatLng? _userLoc;
  String? _selectedJeepId;

  bool _hasSetDestination = false;
  bool _hasSelectedJeep = false;
  bool _isFollowing = true;
  bool _showHint = true;
  bool _isLocationInitialized = false;
  bool _isProfileIncomplete = false;

  Map<String, Map<String, dynamic>> _jeepneys = {};
  StreamSubscription? _rtdbStream;
  StreamSubscription<Position>? _positionStream;
  final Set<Polyline> _polylines = {};

  // Route matching variables
  final double _routeMatchingThreshold = 2.0; // km threshold for route matching

  @override
  void initState() {
    super.initState();
    _initUserLocation();
    _checkProfileCompletion();
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _rtdbStream?.cancel();
    super.dispose();
  }

  Future<void> _checkProfileCompletion() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final doc = await _firestore.collection('users').doc(user.uid).get();
      if (doc.exists) {
        final data = doc.data()!;
        final hasUsername = data['userName'] != null && data['userName'].toString().isNotEmpty;
        final hasContact = data['contact'] != null && data['contact'].toString().isNotEmpty;
        final hasDOB = data['dob'] != null;

        setState(() {
          _isProfileIncomplete = !hasUsername || !hasContact || !hasDOB;
        });
      }
    } catch (e) {
      debugPrint('Error checking profile: $e');
    }
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

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      _updateUserMarker(LatLng(pos.latitude, pos.longitude));

      setState(() {
        _isLocationInitialized = true;
      });

      _positionStream = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ),
      ).listen((p) {
        _updateUserMarker(LatLng(p.latitude, p.longitude));
      });
    } catch (e) {
      debugPrint("Error initializing GPS: $e");
    }
  }

  // ✅ Enhanced location update with debugging
  void _updateUserMarker(LatLng pos) {
    if (pos.latitude == 0.0 && pos.longitude == 0.0) {
      debugPrint("⚠️ Invalid location (0,0) - skipping");
      return;
    }

    debugPrint("📍 Pasahero Location Update: ${pos.latitude}, ${pos.longitude}");

    setState(() => _userLoc = pos);

    final shared = SharedHome.of(context);
    if (shared != null && mounted) {
      debugPrint("📍 Calling SharedHome.updateUserLocation()");
      shared.updateUserLocation(pos);
      shared.removeMarker(const MarkerId('user_marker'));
    } else {
      debugPrint("❌ SharedHome not available");
    }

    _updatePolyline();
  }

  // ✅ Listen to all jeepneys (from RTDB)
  void _listenToJeepneys() {
    _rtdbStream = _rtdbService.devicesRef.onValue.listen((event) {
      final raw = event.snapshot.value;
      if (raw == null) return;
      final Map data = (raw is Map) ? raw : {};
      final updated = <String, Map<String, dynamic>>{};

      final shared = SharedHome.of(context);
      if (shared == null) return;

      // UPDATED CODE:
      for (final entry in data.entries) {
        final id = entry.key;
        final jeep = entry.value;
        if (jeep is Map) {
          final lat = _toDouble(jeep['latitude'] ?? jeep['lat']);
          final lng = _toDouble(jeep['longitude'] ?? jeep['lng']);
          final speed = _toDouble(jeep['speed_kmh'] ?? jeep['speed']);
          final course = _toDouble(jeep['course']);
          final isOnline = jeep['isOnline'] == true;
          final currentPassengers = (jeep['currentPassengers'] as int?) ?? 0;
          final maxCapacity = (jeep['maxCapacity'] as int?) ?? 20;

          if (lat != null && lng != null) {
            updated[id] = {
              'lat': lat,
              'lng': lng,
              'speed': speed ?? 0,
              'course': course ?? 0,
              'isOnline': isOnline,
              'currentPassengers': currentPassengers,
              'maxCapacity': maxCapacity,
              'hasAvailableSeats': currentPassengers < maxCapacity,
              'jeepneyPos': LatLng(lat, lng),
            };

            // ✅ ADDED: Create marker with zoom-aware icon
            final sharedHome = SharedHome.of(context);
            if (sharedHome != null) {
              // Use medium icon by default (will be updated by SharedHome's zoom logic)
              final marker = Marker(
                markerId: MarkerId('jeep_$id'),
                position: LatLng(lat, lng),
                icon: AppIcons.jeepIconMedium ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
                infoWindow: InfoWindow(
                  title: 'Jeepney $id',
                  snippet: 'Speed: ${(speed ?? 0).toStringAsFixed(1)} km/h | Passengers: $currentPassengers/$maxCapacity',
                ),
                rotation: course ?? 0,
                anchor: const Offset(0.5, 0.5),
                flat: true,
              );

              // Add marker to SharedHome for proper zoom handling
              sharedHome.addOrUpdateMarker(MarkerId('jeep_$id'), marker);
            }
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

  // ✅ Enhanced Route Matching Logic
  bool _isJeepneyOnRoute(String jeepneyId) {
    if (_destination == null || _userLoc == null) return false;

    final jeepney = _jeepneys[jeepneyId];
    if (jeepney == null) return false;

    final jeepneyPos = LatLng(jeepney['lat'], jeepney['lng']);

    // Simple route matching: check if jeepney is between user and destination
    final userToDestDistance = _distanceKm(_userLoc!, _destination!);
    final userToJeepDistance = _distanceKm(_userLoc!, jeepneyPos);
    final jeepToDestDistance = _distanceKm(jeepneyPos, _destination!);

    // Jeepney is considered "on route" if it's reasonably close to the path
    // between user and destination (using triangle inequality)
    final totalDirectDistance = userToDestDistance;
    final actualDistance = userToJeepDistance + jeepToDestDistance;

    // If actual distance is within threshold of direct distance, consider it on route
    return (actualDistance - totalDirectDistance) <= _routeMatchingThreshold;
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

    // Start listening to jeepneys after destination is set
    if (_rtdbStream == null) {
      _listenToJeepneys();
    }
  }

  // ✅ FIXED: Enhanced PARA! signal with profile completion check
  Future<void> _sendParaSignal() async {
    // Check profile completion first
    if (_isProfileIncomplete) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ Please complete your profile in Settings to use PARA!'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_selectedJeepId == null || _userLoc == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ Please select a jeepney first'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_destination == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ Please set your destination first'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final selectedJeep = _jeepneys[_selectedJeepId];
    if (selectedJeep == null || selectedJeep['isOnline'] != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ Selected jeepney is no longer available'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Check capacity
    if (selectedJeep['hasAvailableSeats'] != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Jeepney is full (${selectedJeep['currentPassengers']}/${selectedJeep['maxCapacity']})'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Check route matching
    if (!_isJeepneyOnRoute(_selectedJeepId!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ Selected jeepney is not on your route'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _hasSelectedJeep = false;
    });

    try {
      final baseFare = 15.00;
      final isDigitalPayment = true; // Demo - assume digital payment

      final docRef = await _firestore.collection('para_requests').add({
        'jeepneyId': _selectedJeepId,
        'passengerId': _auth.currentUser?.uid,
        'passengerName': _auth.currentUser?.displayName ?? 'Passenger',
        'passengerLocation': GeoPoint(_userLoc!.latitude, _userLoc!.longitude),
        'destination': GeoPoint(_destination!.latitude, _destination!.longitude),
        'status': 'pending',
        'timestamp': FieldValue.serverTimestamp(),
        'fare': baseFare,
        'paymentMethod': isDigitalPayment ? 'digital' : 'cash',
        'isDigitalPayment': isDigitalPayment,
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('🚍 PARA! signal sent to Jeepney $_selectedJeepId'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );

      debugPrint("✅ PARA! request sent with ID: ${docRef.id}");

      // Reset selection
      setState(() {
        _selectedJeepId = null;
        _hasSelectedJeep = false;
      });

      _updatePolyline();

    } catch (e) {
      debugPrint("❌ Failed to send PARA! signal: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Failed to send PARA! signal: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  // ✅ Enhanced jeepney suggestion list with route matching and capacity info
  Widget _buildJeepneySuggestionList() {
    if (!_hasSetDestination) return const SizedBox.shrink();

    // Filter online jeepneys with available seats AND on route
    final availableJeepneys = _jeepneys.entries.where((entry) =>
    entry.value['isOnline'] == true &&
        entry.value['hasAvailableSeats'] == true &&
        _isJeepneyOnRoute(entry.key)
    );

    if (availableJeepneys.isEmpty) {
      return _buildInfoCard("No available jeepneys with seats on your route nearby.");
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
            "Available Jeepneys (On Your Route)",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 8),
          ...availableJeepneys.map((entry) {
            final id = entry.key;
            final data = entry.value;
            LatLng jeepPos = LatLng(data['lat'], data['lng']);
            double? eta;
            if (_userLoc != null) {
              eta = _computeETA(jeepPos, _userLoc!, data['speed'] ?? 20);
            }

            final currentPassengers = data['currentPassengers'] ?? 0;
            final maxCapacity = data['maxCapacity'] ?? 20;
            final availableSeats = maxCapacity - currentPassengers;

            return ListTile(
              leading: const Icon(Icons.directions_bus, color: Colors.green),
              title: Text("Jeepney $id"),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    eta != null && eta != double.infinity
                        ? "ETA: ${eta.toStringAsFixed(1)} min"
                        : "Calculating ETA...",
                  ),
                  Text(
                    "👥 $currentPassengers/$maxCapacity passengers",
                    style: TextStyle(
                      color: availableSeats > 0 ? Colors.green : Colors.red,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    "🪑 $availableSeats seats available",
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
              trailing: _selectedJeepId == id
                  ? const Icon(Icons.check_circle, color: Colors.green)
                  : const Icon(Icons.radio_button_unchecked, color: Colors.grey),
              onTap: () {
                setState(() {
                  _selectedJeepId = id;
                  _hasSelectedJeep = true;
                  _updatePolyline();
                });

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('✅ Selected Jeepney $id ($availableSeats seats available)'),
                    duration: const Duration(seconds: 1),
                  ),
                );
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
      color: const Color.fromARGB(255, 255, 255, 255),
      borderRadius: BorderRadius.circular(12),
      boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8)],
    ),
    child: Center(child: Text(text)),
  );

  Widget _buildParaButton() {
    final isProfileComplete = !_isProfileIncomplete;
    final isEnabled = _hasSetDestination && _hasSelectedJeep && isProfileComplete;

    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 20.0),
        child: ElevatedButton(
          onPressed: isEnabled ? _sendParaSignal : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: isEnabled
                ? Colors.greenAccent.shade700
                : Colors.grey,
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30),
            ),
          ),
          child: _isProfileIncomplete
              ? const Text(
            'Complete Profile First',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: Colors.white,
            ),
          )
              : const Text(
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

  // ✅ ADDED: Compact ads button for top-right
  Widget _buildCompactAdsButton() {
    return Positioned(
      top: 80,
      right: 16,
      child: CompactAdsButton(
        onPointsUpdate: () {
          // Refresh points if needed
          setState(() {});
        },
      ),
    );
  }

  List<Widget> _buildPasaheroMenu() => [
    Container(
      margin: EdgeInsets.only(top: 15,right: 15,bottom: 8),
      decoration: BoxDecoration(
      color: const Color.fromARGB(255, 40, 36, 41),
      borderRadius: BorderRadius.only(topRight: Radius.circular(17),bottomRight: Radius.circular(17)),
      ),
      child: Column (
        
        children: [
    
   ListTile(
    visualDensity: const VisualDensity(vertical: -4),
      leading: const Icon(Icons.history),
      title: const Text('Biyahe Logs'),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => BiyaheLogsPage(userType: 'pasahero'), // or 'tsuperhero'
          ),
        );
      },
    ),
    const Divider(
      color:  Color.fromARGB(255, 52, 46, 53),),
    
    ListTile(
      visualDensity: const VisualDensity(vertical: -4),
      leading: const Icon(Icons.person),
      title: const Text('Profile Settings'),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ProfileSettingsPage()),
        ).then((_) => _checkProfileCompletion());
      },
    ),
    const Divider(
      color:  Color.fromARGB(255, 52, 46, 53),),
    ListTile(
      visualDensity: const VisualDensity(vertical: -4),
      leading: const Icon(Icons.settings),
      title: const Text('Settings'),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ProfileSettingsPage()),
        );
      },
      trailing: IconButton(
        icon: const Icon(Icons.brightness_6),
        tooltip: 'Toggle map theme',
        color: Colors.white,
        onPressed: () => ButtonActions.toggleMapTheme(context, null),
      ),
    ),
    const Divider(
      color:  Color.fromARGB(255, 52, 46, 53),),
    ListTile(
      visualDensity: const VisualDensity(vertical: -4),
      leading: const Icon(Icons.qr_code_2),
      title: const Text('Scan QR to Become Tsuperhero'),
      titleTextStyle: TextStyle(fontSize: 13),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const QRScanPage()),
        );
      },
    ),
    
    ],
    ),
    ),
  ];

  Future<void> _handleSignOut() async {
    _positionStream?.cancel();
    _rtdbStream?.cancel();
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
    if (userLoc != null && _userLoc == null) {
      _userLoc = userLoc;
    }

    _updatePolyline();

    return Stack(
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_showHint && _isLocationInitialized)
            _buildJeepneySuggestionList(),
            _buildParaButton(),
          ],
        ),

        // ✅ ADDED: Compact ads button positioned in top-right
        _buildCompactAdsButton(),
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