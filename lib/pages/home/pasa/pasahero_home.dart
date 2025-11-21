// lib/pages/home/pasahero_home.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:para2/pages/home/shared_home.dart';
import 'package:para2/services/location_broadcast.dart';
import 'package:para2/pages/login/login.dart';
import 'package:para2/pages/login/qr_scan_page.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:math' as math;
import 'dart:io';
import 'package:para2/theme/app_icons.dart';
import 'package:para2/pages/settings/profile_settings.dart';
import 'package:para2/services/RealtimeDatabaseService.dart';
import 'package:para2/services/button_actions.dart';
import 'package:para2/services/snackbar_service.dart';
import 'package:para2/services/map_theme_service.dart';
import 'package:para2/widgets/compact_ads_button.dart';
import 'package:para2/pages/biyahe/biyahe_logs_page.dart';

class PasaheroHome extends StatefulWidget {
  const PasaheroHome({super.key});
  

  @override
  State<PasaheroHome> createState() => _PasaheroHomeState();
}

class _PasaheroHomeState extends State<PasaheroHome> with WidgetsBindingObserver {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final RealtimeDatabaseService _rtdbService = RealtimeDatabaseService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  LatLng? _destination;
  LatLng? _userLoc;
  String? _selectedJeepId;

  bool _hasSetDestination = false;
  bool _hasSelectedJeep = false;
  // _isFollowing removed; follow handled by FollowService / SharedHome
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
    WidgetsBinding.instance.addObserver(this);
    _initUserLocation();
    _checkProfileCompletion();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _positionStream?.cancel().then((_) {
      _positionStream = null;
    });
    _rtdbStream?.cancel().then((_) {
      _rtdbStream = null;
    });
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    debugPrint('PasaheroHome lifecycle: $state');
    if (state == AppLifecycleState.resumed) {
      // Restart the position stream when app resumes
      _startPositionStream();
    } else if (state == AppLifecycleState.paused) {
      // Pause subscription to conserve resources; will be restarted on resume
      _positionStream?.pause();
    }
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
        SnackbarService.show(context, '⚠️ Please enable GPS service.');
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        SnackbarService.show(context, '❌ Location permission denied.');
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      _updateUserMarker(LatLng(pos.latitude, pos.longitude));

      setState(() {
        _isLocationInitialized = true;
      });

      // Start a lifecycle-aware position stream
      await _startPositionStream();
    } catch (e) {
      debugPrint("Error initializing GPS: $e");
    }
  }

  /// Start position stream if not already started. This method guards
  /// against double subscriptions and logs updates/errors for debugging.
  Future<void> _startPositionStream() async {
    try {
      if (_positionStream != null) {
        // If paused, resume
        try {
          _positionStream?.resume();
        } catch (_) {}
        debugPrint('Position stream already active or resumed');
        return;
      }

      final settings = Platform.isAndroid
          ? AndroidSettings(
              accuracy: LocationAccuracy.best,
              distanceFilter: 0,
              intervalDuration: const Duration(milliseconds: 333),
            )
          : const LocationSettings(
              accuracy: LocationAccuracy.best,
              distanceFilter: 0,
            );

      _positionStream = Geolocator.getPositionStream(locationSettings: settings)
          .listen((p) {
        debugPrint('Position stream update: ${p.latitude}, ${p.longitude}');
        _updateUserMarker(LatLng(p.latitude, p.longitude));
      }, onError: (err) {
        debugPrint('Position stream error: $err');
      }, onDone: () {
        debugPrint('Position stream done');
        _positionStream = null;
      });

      debugPrint('Position stream started');
    } catch (e) {
      debugPrint('Failed to start position stream: $e');
    }
  }

  // ✅ Enhanced location update with debugging
  void _updateUserMarker(LatLng pos) {
    if (pos.latitude == 0.0 && pos.longitude == 0.0) {
      debugPrint("⚠️ Invalid location (0,0) - skipping");
      return;
    }

    debugPrint("Pasahero Location Update: ${pos.latitude}, ${pos.longitude}");

    setState(() => _userLoc = pos);

    // Publish location to the app-wide broadcaster. SharedHome subscribes
    // to this stream and will update the map marker regardless of ancestor
    // lookup availability.
    try {
      final emitTs = DateTime.now().millisecondsSinceEpoch;
      debugPrint('emit_ts=$emitTs Publishing location: $pos');
      LocationBroadcast.instance.emit(pos);
      debugPrint('📍 Published location to LocationBroadcast: $pos');
    } catch (e) {
      debugPrint('❌ Failed to publish location: $e');
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
      SnackbarService.show(context, '❌ Please complete your profile in Settings to use PARA!');
      return;
    }

    if (_selectedJeepId == null || _userLoc == null) {
      SnackbarService.show(context, '❌ Please select a jeepney first');
      return;
    }

    if (_destination == null) {
      SnackbarService.show(context, '❌ Please set your destination first');
      return;
    }

    final selectedJeep = _jeepneys[_selectedJeepId];
    if (selectedJeep == null || selectedJeep['isOnline'] != true) {
      SnackbarService.show(context, '❌ Selected jeepney is no longer available');
      return;
    }

    // Check capacity
    if (selectedJeep['hasAvailableSeats'] != true) {
      SnackbarService.show(context, '❌ Jeepney is full (${selectedJeep['currentPassengers']}/${selectedJeep['maxCapacity']})');
      return;
    }

    // Check route matching
    if (!_isJeepneyOnRoute(_selectedJeepId!)) {
      SnackbarService.show(context, '❌ Selected jeepney is not on your route');
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

      SnackbarService.show(context, '🚍 PARA! signal sent to Jeepney $_selectedJeepId', duration: const Duration(seconds: 3));

      debugPrint("✅ PARA! request sent with ID: ${docRef.id}");

      // Reset selection
      setState(() {
        _selectedJeepId = null;
        _hasSelectedJeep = false;
      });

      _updatePolyline();

    } catch (e) {
      debugPrint("❌ Failed to send PARA! signal: $e");
      SnackbarService.show(context, '❌ Failed to send PARA! signal: $e', duration: const Duration(seconds: 3));
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

    // When compact is true we render a condensed widget suitable for a row
    if (compact) {
      if (availableJeepneys.isEmpty) {
        return SizedBox(
          width: 180,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'No jeepneys on your route',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
        );
      }

      // Show up to 2 items in compact mode to fit in a row
      final items = availableJeepneys.take(2).map((entry) {
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

        return GestureDetector(
          onTap: () {
            setState(() {
              _selectedJeepId = id;
              _hasSelectedJeep = true;
              _updatePolyline();
            });
            SnackbarService.show(context, '✅ Selected Jeepney $id ($availableSeats seats available)', duration: const Duration(seconds: 1));
          },
          child: Container(
            width: 180,
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Jeep $id', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 6),
                Text(eta != null && eta != double.infinity ? '${eta.toStringAsFixed(1)} min' : 'Calculating', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(height: 6),
                Text('$availableSeats seats', style: const TextStyle(color: Colors.greenAccent, fontSize: 12)),
              ],
            ),
          ),
        );
      }).toList();

      return Row(children: items);
    }

    // Default (full) layout
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

                SnackbarService.show(context, '✅ Selected Jeepney $id ($availableSeats seats available)', duration: const Duration(seconds: 1));
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
    
      padding: const EdgeInsets.only(top: 10, bottom: 10),
      margin: EdgeInsets.only(right: 10,bottom: 8),
      decoration: BoxDecoration(
      color: const Color.fromARGB(255, 23, 22, 27),
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
      leading: ValueListenableBuilder<bool>(
        valueListenable: MapThemeService.instance.isDarkMode,
        builder: (context, isDark, child) {
          return Icon(isDark ? Icons.dark_mode : Icons.light_mode);
        },
      ),
      title: const Text('Display Theme'),
      onTap: () => ButtonActions.toggleMapTheme(context, null),
    ),
    const Divider(
      color:  Color.fromARGB(255, 52, 46, 53),),
    ListTile(
      visualDensity: const VisualDensity(vertical: -4),
      leading: const Icon(Icons.settings_sharp),
      title: const Text('Settings'),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ProfileSettingsPage()),
        );
      },
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
      const Divider(
        color:  Color.fromARGB(255, 52, 46, 53),),



    const SizedBox(height: 70),




    ListTile(
      visualDensity: const VisualDensity(vertical: -4),
      leading: const Icon(Icons.feedback),
      title: const Text('Feedback'),
      titleTextStyle: TextStyle(fontSize: 13),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const QRScanPage()),
        );
      },
    ),
    
    ListTile(
      visualDensity: const VisualDensity(vertical: -4),
      leading: const Icon(Icons.handshake),
      title: const Text('Support Us'),
      titleTextStyle: TextStyle(fontSize: 13),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const QRScanPage()),
        );
      },
    ),

    ListTile(
      visualDensity: const VisualDensity(vertical: -4),
      leading: const Icon(Icons.book),
      title: const Text('Terms and Conditions'),
      titleTextStyle: TextStyle(fontSize: 13),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const QRScanPage()),
        );
      },
    ),
    ListTile(
      visualDensity: const VisualDensity(vertical: -4),
      leading: const Icon(Icons.help_center_rounded),
      title: const Text('About PARA!'),
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

  List<Widget> _buildPasaheroActions() => [
    Column(
      children: [
        Row(
          children: [

            SingleChildScrollView(
              child: _buildJeepneySuggestionList()),
            
            
            
             


          ],
        ),
      ],

    )




  ];

  Future<void> _handleSignOut() async {
    await _positionStream?.cancel();
    _positionStream = null;
    await _rtdbStream?.cancel();
    _rtdbStream = null;
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
      roleActions: _buildPasaheroActions(),
      roleContentBuilder: _buildRoleContent,
      onMapTap: _onMapTap,

    );
  }
}