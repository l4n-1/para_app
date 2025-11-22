For pasahero_home.dart
// lib/pages/home/pasahero_home.dart
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

import 'package:para2/data/jeepney_routes.dart';
import 'package:para2/pages/biyahe/biyahe_logs_page.dart';
import 'package:para2/pages/home/shared_home.dart';
import 'package:para2/pages/login/login.dart';
import 'package:para2/pages/login/qr_scan_page.dart';
import 'package:para2/pages/settings/profile_settings.dart';
import 'package:para2/services/RealtimeDatabaseService.dart';
import 'package:para2/services/button_actions.dart';
import 'package:para2/services/location_broadcast.dart';
import 'package:para2/services/map_theme_service.dart';
import 'package:para2/services/snackbar_service.dart';
import 'package:para2/theme/app_icons.dart';
import 'package:para2/widgets/compact_ads_button.dart';

class PasaheroHome extends StatefulWidget {
  const PasaheroHome({super.key});

  @override
  State<PasaheroHome> createState() => _PasaheroHomeState();
}

class _PasaheroHomeState extends State<PasaheroHome>
    with WidgetsBindingObserver {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final RealtimeDatabaseService _rtdbService = RealtimeDatabaseService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // 🔑 Replace this with your real API key, and keep it out of git ideally.
  static const String _googleApiKey = 'AIzaSyCb4q7iicIT4TD8qjPQxHtlxYn4tEj4WOY';

  late final PolylinePoints _polylinePoints;

  LatLng? _destination;
  LatLng? _userLoc;
  String? _selectedJeepId;

  bool _hasSetDestination = false;
  bool _hasSelectedJeep = false;
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

    // ✅ Correct for flutter_polyline_points 2.1.0 — no apiKey in constructor
    _polylinePoints = PolylinePoints();

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
      _startPositionStream();
    } else if (state == AppLifecycleState.paused) {
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
        final hasUsername = data['userName'] != null &&
            data['userName'].toString().isNotEmpty;
        final hasContact = data['contact'] != null &&
            data['contact'].toString().isNotEmpty;
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

      await _startPositionStream();
    } catch (e) {
      debugPrint("Error initializing GPS: $e");
    }
  }

  Future<void> _startPositionStream() async {
    try {
      if (_positionStream != null) {
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

      _positionStream =
          Geolocator.getPositionStream(locationSettings: settings).listen(
                (p) {
              debugPrint('Position stream update: ${p.latitude}, ${p.longitude}');
              _updateUserMarker(LatLng(p.latitude, p.longitude));
            },
            onError: (err) {
              debugPrint('Position stream error: $err');
            },
            onDone: () {
              debugPrint('Position stream done');
              _positionStream = null;
            },
          );

      debugPrint('Position stream started');
    } catch (e) {
      debugPrint('Failed to start position stream: $e');
    }
  }

  void _updateUserMarker(LatLng pos) {
    if (pos.latitude == 0.0 && pos.longitude == 0.0) {
      debugPrint("⚠️ Invalid location (0,0) - skipping");
      return;
    }

    debugPrint("Pasahero Location Update: ${pos.latitude}, ${pos.longitude}");

    setState(() => _userLoc = pos);

    try {
      final emitTs = DateTime.now().millisecondsSinceEpoch;
      debugPrint('emit_ts=$emitTs Publishing location: $pos');
      LocationBroadcast.instance.emit(pos);
      debugPrint('📍 Published location to LocationBroadcast: $pos');
    } catch (e) {
      debugPrint('❌ Failed to publish location: $e');
    }

    _updatePolyline();
    if (_destination != null) {
      _buildRoutePolyline();
    }
  }

  // ✅ Listen to all jeepneys (from RTDB)
  void _listenToJeepneys() {
    _rtdbStream = _rtdbService.devicesRef.onValue.listen((event) {
      final raw = event.snapshot.value;
      if (raw == null) return;
      final Map data = (raw is Map) ? raw : {};
      final updated = <String, Map<String, dynamic>>{};

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
              'routeId': jeep['routeId'],
            };

            final sharedHome = SharedHome.of(context);
            if (sharedHome != null) {
              final marker = Marker(
                markerId: MarkerId('jeep_$id'),
                position: LatLng(lat, lng),
                icon: AppIcons.jeepIconMedium ??
                    BitmapDescriptor.defaultMarkerWithHue(
                        BitmapDescriptor.hueGreen),
                infoWindow: InfoWindow(
                  title: 'Jeepney $id',
                  snippet:
                  'Speed: ${(speed ?? 0).toStringAsFixed(1)} km/h | Passengers: $currentPassengers/$maxCapacity',
                ),
                rotation: course ?? 0,
                anchor: const Offset(0.5, 0.5),
                flat: true,
              );

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

  bool _isJeepneyOnRoute(String jeepneyId) {
    if (_destination == null || _userLoc == null) return false;

    final jeepney = _jeepneys[jeepneyId];
    if (jeepney == null) return false;

    final routeId = jeepney['routeId'] as String?;
    if (routeId == null) return false;

    final route = kJeepneyRoutes[routeId];
    if (route == null || route.points.length < 2) return false;

    final jeepPos = LatLng(jeepney['lat'], jeepney['lng']);

    const double maxDestDistanceKm = 0.3;
    final destToRoute = _distanceToPolylineKm(_destination!, route.points);
    if (destToRoute > maxDestDistanceKm) {
      return false;
    }

    final userIdx = _closestPointIndexOnRoute(_userLoc!, route.points);
    final destIdx = _closestPointIndexOnRoute(_destination!, route.points);
    final jeepIdx = _closestPointIndexOnRoute(jeepPos, route.points);

    if (userIdx == -1 || destIdx == -1 || jeepIdx == -1) return false;

    return _isJeepneyAheadOnRoute(
      userIdx: userIdx,
      destIdx: destIdx,
      jeepIdx: jeepIdx,
    );
  }

  double _degToRad(double deg) => deg * math.pi / 180;

  double _distanceKm(LatLng a, LatLng b) {
    const R = 6371;
    final dLat = _degToRad(b.latitude - a.latitude);
    final dLon = _degToRad(b.longitude - a.longitude);
    final aVal = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degToRad(a.latitude)) *
            math.cos(_degToRad(b.latitude)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return R * 2 * math.atan2(math.sqrt(aVal), math.sqrt(1 - aVal));
  }

  double _distancePointToSegmentKm(LatLng p, LatLng a, LatLng b) {
    final px = p.latitude;
    final py = p.longitude;
    final ax = a.latitude;
    final ay = a.longitude;
    final bx = b.latitude;
    final by = b.longitude;

    final abx = bx - ax;
    final aby = by - ay;
    final apx = px - ax;
    final apy = py - ay;

    final abLen2 = abx * abx + aby * aby;
    if (abLen2 == 0) {
      return _distanceKm(p, a);
    }

    double t = (apx * abx + apy * aby) / abLen2;
    if (t < 0) t = 0;
    if (t > 1) t = 1;

    final proj = LatLng(ax + abx * t, ay + aby * t);
    return _distanceKm(p, proj);
  }

  double _distanceToPolylineKm(LatLng p, List<LatLng> polyline) {
    if (polyline.length < 2) return double.infinity;
    double minDist = double.infinity;
    for (var i = 0; i < polyline.length - 1; i++) {
      final d = _distancePointToSegmentKm(p, polyline[i], polyline[i + 1]);
      if (d < minDist) minDist = d;
    }
    return minDist;
  }

  int _closestPointIndexOnRoute(LatLng p, List<LatLng> route) {
    if (route.isEmpty) return -1;
    int bestIndex = 0;
    double bestDist = _distanceKm(p, route[0]);

    for (var i = 1; i < route.length; i++) {
      final d = _distanceKm(p, route[i]);
      if (d < bestDist) {
        bestDist = d;
        bestIndex = i;
      }
    }
    return bestIndex;
  }

  bool _isJeepneyAheadOnRoute({
    required int userIdx,
    required int destIdx,
    required int jeepIdx,
  }) {
    if (destIdx > userIdx) {
      return jeepIdx >= userIdx && jeepIdx <= destIdx;
    } else if (destIdx < userIdx) {
      return jeepIdx <= userIdx && jeepIdx >= destIdx;
    } else {
      return false;
    }
  }

  double _computeETA(LatLng from, LatLng to, double speedKmh) {
    final dist = _distanceKm(from, to);
    if (speedKmh <= 0) return double.infinity;
    return (dist / speedKmh) * 60;
  }

  double _estimateFare(double distanceKm) {
    // Super simple placeholder formula:
    // base fare ₱15 + ₱2 per km
    const double baseFare = 15.0;
    const double perKm = 2.0;
    return baseFare + distanceKm * perKm;
  }

  String _formatDistance(double km) {
    if (km < 1.0) {
      return '${(km * 1000).round()} m';
    }
    return '${km.toStringAsFixed(1)} km';
  }

  // ✅ Update lines connecting passenger, jeep, destination
  void _updatePolyline() {
    _polylines.removeWhere(
          (p) => p.polylineId.value == 'trackingLine',
    );

    debugPrint(
      'updatePolyline: userLoc=$_userLoc dest=$_destination '
          'selectedJeep=$_selectedJeepId hasSelectedJeep=$_hasSelectedJeep',
    );

    if (_userLoc == null) {
      debugPrint('updatePolyline: userLoc is null -> no polylines');
      return;
    }

    if (_hasSelectedJeep &&
        _selectedJeepId != null &&
        _jeepneys[_selectedJeepId] != null) {
      final jeep = _jeepneys[_selectedJeepId]!;
      final jeepPos = LatLng(jeep['lat'], jeep['lng']);
      final tracking = Polyline(
        polylineId: const PolylineId("trackingLine"),
        color: Colors.green,
        width: 4,
        points: [_userLoc!, jeepPos],
      );
      _polylines.add(tracking);
      debugPrint('updatePolyline: added trackingLine');
    } else {
      debugPrint('updatePolyline: no selected jeep / no jeep data');
    }

    final shared = SharedHome.of(context);
    shared?.setExternalPolylines(_polylines);
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

    await _buildRoutePolyline();

    if (_rtdbStream == null) {
      _listenToJeepneys();
    }
  }

  // 🚍 PARA! signal
  Future<void> _sendParaSignal() async {
    if (_isProfileIncomplete) {
      SnackbarService.show(
          context, '❌ Please complete your profile in Settings to use PARA!');
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
      SnackbarService.show(
          context, '❌ Selected jeepney is no longer available');
      return;
    }

    if (selectedJeep['hasAvailableSeats'] != true) {
      SnackbarService.show(
          context,
          '❌ Jeepney is full (${selectedJeep['currentPassengers']}/'
              '${selectedJeep['maxCapacity']})');
      return;
    }

    if (!_isJeepneyOnRoute(_selectedJeepId!)) {
      SnackbarService.show(
          context, '❌ Selected jeepney is not on your route');
      return;
    }

    setState(() {
      _hasSelectedJeep = false;
    });

    try {
      final baseFare = 15.00;
      final isDigitalPayment = true;

      final docRef = await _firestore.collection('para_requests').add({
        'jeepneyId': _selectedJeepId,
        'passengerId': _auth.currentUser?.uid,
        'passengerName': _auth.currentUser?.displayName ?? 'Passenger',
        'passengerLocation':
        GeoPoint(_userLoc!.latitude, _userLoc!.longitude),
        'destination':
        GeoPoint(_destination!.latitude, _destination!.longitude),
        'status': 'pending',
        'timestamp': FieldValue.serverTimestamp(),
        'fare': baseFare,
        'paymentMethod': isDigitalPayment ? 'digital' : 'cash',
        'isDigitalPayment': isDigitalPayment,
      });

      SnackbarService.show(
        context,
        '🚍 PARA! signal sent to Jeepney $_selectedJeepId',
        duration: const Duration(seconds: 3),
      );

      debugPrint("✅ PARA! request sent with ID: ${docRef.id}");

      setState(() {
        _selectedJeepId = null;
        _hasSelectedJeep = false;
      });

      _updatePolyline();
    } catch (e) {
      debugPrint("❌ Failed to send PARA! signal: $e");
      SnackbarService.show(
        context,
        '❌ Failed to send PARA! signal: $e',
        duration: const Duration(seconds: 3),
      );
    }
  }

  Widget _buildJeepneySuggestionList({bool compact = false}) {
    if (!_hasSetDestination) return const SizedBox.shrink();

    final availableJeepneys = _jeepneys.entries.where((entry) =>
    entry.value['isOnline'] == true &&
        entry.value['hasAvailableSeats'] == true &&
        _isJeepneyOnRoute(entry.key));

    if (compact) {
      if (availableJeepneys.isEmpty) {
        return SizedBox(
          width: 180,
          child: Container(
            padding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
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

      final items = availableJeepneys.take(2).map((entry) {
        final id = entry.key;
        final data = entry.value;
        LatLng jeepPos = LatLng(data['lat'], data['lng']);
        double? eta;
        if (_userLoc != null) {
          eta = _computeETA(
              jeepPos, _userLoc!, data['speed'] ?? 20);
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
            SnackbarService.show(
              context,
              '✅ Selected Jeepney $id ($availableSeats seats available)',
              duration: const Duration(seconds: 1),
            );
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
                Text('Jeep $id',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13)),
                const SizedBox(height: 6),
                Text(
                  eta != null && eta != double.infinity
                      ? '${eta.toStringAsFixed(1)} min'
                      : 'Calculating',
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 6),
                Text(
                  '$availableSeats seats',
                  style: const TextStyle(
                      color: Colors.greenAccent, fontSize: 12),
                ),
              ],
            ),
          ),
        );
      }).toList();

      return Row(children: items);
    }

    if (availableJeepneys.isEmpty) {
      return _buildInfoCard(
          "No available jeepneys with seats on your route nearby.");
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
            style:
            TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 8),
          ...availableJeepneys.map((entry) {
            final id = entry.key;
            final data = entry.value;
            LatLng jeepPos = LatLng(data['lat'], data['lng']);
            double? eta;
            if (_userLoc != null) {
              eta = _computeETA(
                  jeepPos, _userLoc!, data['speed'] ?? 20);
            }

            final currentPassengers = data['currentPassengers'] ?? 0;
            final maxCapacity = data['maxCapacity'] ?? 20;
            final availableSeats = maxCapacity - currentPassengers;

            return ListTile(
              leading: const Icon(Icons.directions_bus,
                  color: Colors.green),
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
                      color: availableSeats > 0
                          ? Colors.green
                          : Colors.red,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    "🪑 $availableSeats seats available",
                    style: const TextStyle(
                        fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
              trailing: _selectedJeepId == id
                  ? const Icon(Icons.check_circle, color: Colors.green)
                  : const Icon(Icons.radio_button_unchecked,
                  color: Colors.grey),
              onTap: () {
                setState(() {
                  _selectedJeepId = id;
                  _hasSelectedJeep = true;
                  _updatePolyline();
                });

                SnackbarService.show(
                  context,
                  '✅ Selected Jeepney $id ($availableSeats seats available)',
                  duration: const Duration(seconds: 1),
                );
              },
            );
          }),
        ],
      ),
    );
  }

  Widget _buildDestinationSheet() {
    // Only show when user has tapped a destination
    if (!_hasSetDestination || _destination == null) {
      return const SizedBox.shrink();
    }

    final hasUser = _userLoc != null;
    final double? distanceKm =
    hasUser ? _distanceKm(_userLoc!, _destination!) : null;
    final double? approxFare =
    distanceKm != null ? _estimateFare(distanceKm) : null;

    // Figure out which jeep is "selected" for the details area:
    // 1) If user has tapped one -> use that
    // 2) Else, use the first available jeep on route (if any)
    MapEntry<String, Map<String, dynamic>>? selectedEntry;

    if (_selectedJeepId != null && _jeepneys[_selectedJeepId] != null) {
      selectedEntry = MapEntry(_selectedJeepId!, _jeepneys[_selectedJeepId!]!);
    } else {
      final availableJeepneys = _jeepneys.entries.where((entry) =>
      entry.value['isOnline'] == true &&
          entry.value['hasAvailableSeats'] == true &&
          _isJeepneyOnRoute(entry.key));
      if (availableJeepneys.isNotEmpty) {
        selectedEntry = availableJeepneys.first;
      }
    }

    final String? selectedJeepId = selectedEntry?.key;
    final Map<String, dynamic>? selectedJeep = selectedEntry?.value;
    final String? routeId =
    selectedJeep != null ? selectedJeep['routeId'] as String? : null;

    final bool canPara = !_isProfileIncomplete &&
        selectedJeepId != null &&
        hasUser &&
        _destination != null;

    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        minimum: const EdgeInsets.only(left: 8, right: 8, bottom: 8),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          decoration: BoxDecoration(
            color: const Color(0xFF181820),
            borderRadius: BorderRadius.circular(18),
            boxShadow: const [
              BoxShadow(
                color: Colors.black54,
                blurRadius: 16,
                offset: Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // little drag handle
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // Destination + distance + fare
              Row(
                children: [
                  const Icon(Icons.flag, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'To your selected destination',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              if (distanceKm != null) ...[
                const SizedBox(height: 4),
                Text(
                  '${_formatDistance(distanceKm)} away'
                      '${approxFare != null ? ' • Approx fare ₱${approxFare.toStringAsFixed(0)}' : ''}',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
              ],
              const SizedBox(height: 12),

              // Horizontal jeepney cards (reusing your existing builder in compact mode)
              SizedBox(
                height: 100,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: _buildJeepneySuggestionList(compact: true),
                ),
              ),

              const SizedBox(height: 10),

              // Selected jeep details + PARA button
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Left side: jeep + route info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (selectedJeepId != null)
                          Text(
                            'Jeep: $selectedJeepId',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        const SizedBox(height: 4),
                        if (routeId != null)
                          Text(
                            'Route: $routeId',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          )
                        else
                          const Text(
                            'No route info',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 12),

                  // Right side: PARA button (moved here)
                  ElevatedButton(
                    onPressed: canPara ? _sendParaSignal : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                      canPara ? Colors.greenAccent.shade700 : Colors.grey,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 28, vertical: 12),
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
                ],
              ),
            ],
          ),
        ),
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
    final isEnabled =
        _hasSetDestination && _hasSelectedJeep && isProfileComplete;

    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 20.0),
        child: ElevatedButton(
          onPressed: isEnabled ? _sendParaSignal : null,
          style: ElevatedButton.styleFrom(
            backgroundColor:
            isEnabled ? Colors.greenAccent.shade700 : Colors.grey,
            padding:
            const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
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

  Widget _buildDestinationBar() {
    String label;
    if (_destination == null) {
      label = 'Tap on the map to set your destination';
    } else {
      label =
      'Destination set ✓  (tap another spot on the map to change)';
    }

    return Align(
      alignment: Alignment.topCenter,
      child: SafeArea(
        child: Container(
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.7),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.place, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_destination != null) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _destination = null;
                      _hasSetDestination = false;
                      _selectedJeepId = null;
                      _hasSelectedJeep = false;
                      _polylines.clear();
                      SharedHome.of(context)?.removeMarker(
                        const MarkerId('destination_marker'),
                      );
                    });
                  },
                  child: const Icon(Icons.close,
                      color: Colors.white, size: 16),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompactAdsButton() {
    return Positioned(
      top: 80,
      right: 16,
      child: CompactAdsButton(
        onPointsUpdate: () {
          setState(() {});
        },
      ),
    );
  }

  List<Widget> _buildPasaheroMenu() => [
    Container(
      padding: const EdgeInsets.only(top: 10, bottom: 10),
      margin: const EdgeInsets.only(right: 10, bottom: 8),
      decoration: const BoxDecoration(
        color: Color.fromARGB(255, 23, 22, 27),
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(17),
          bottomRight: Radius.circular(17),
        ),
      ),
      child: Column(
        children: [
          ListTile(
            visualDensity:
            const VisualDensity(vertical: -4),
            leading: const Icon(Icons.history),
            title: const Text('Biyahe Logs'),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      BiyaheLogsPage(userType: 'pasahero'),
                ),
              );
            },
          ),
          const Divider(
            color: Color.fromARGB(255, 52, 46, 53),
          ),
          ListTile(
            visualDensity:
            const VisualDensity(vertical: -4),
            leading: ValueListenableBuilder<bool>(
              valueListenable:
              MapThemeService.instance.isDarkMode,
              builder: (context, isDark, child) {
                return Icon(isDark
                    ? Icons.dark_mode
                    : Icons.light_mode);
              },
            ),
            title: const Text('Display Theme'),
            onTap: () =>
                ButtonActions.toggleMapTheme(context, null),
          ),
          const Divider(
            color: Color.fromARGB(255, 52, 46, 53),
          ),
          ListTile(
            visualDensity:
            const VisualDensity(vertical: -4),
            leading: const Icon(Icons.settings_sharp),
            title: const Text('Settings'),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                  const ProfileSettingsPage(),
                ),
              );
            },
          ),
          const Divider(
            color: Color.fromARGB(255, 52, 46, 53),
          ),
          ListTile(
            visualDensity:
            const VisualDensity(vertical: -4),
            leading: const Icon(Icons.qr_code_2),
            title: const Text(
                'Scan QR to Become Tsuperhero'),
            titleTextStyle: const TextStyle(fontSize: 13),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const QRScanPage(),
                ),
              );
            },
          ),
          const Divider(
            color: Color.fromARGB(255, 52, 46, 53),
          ),
          const SizedBox(height: 70),
          ListTile(
            visualDensity:
            const VisualDensity(vertical: -4),
            leading: const Icon(Icons.feedback),
            title: const Text('Feedback'),
            titleTextStyle: const TextStyle(fontSize: 13),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const QRScanPage(),
                ),
              );
            },
          ),
          ListTile(
            visualDensity:
            const VisualDensity(vertical: -4),
            leading: const Icon(Icons.handshake),
            title: const Text('Support Us'),
            titleTextStyle: const TextStyle(fontSize: 13),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const QRScanPage(),
                ),
              );
            },
          ),
          ListTile(
            visualDensity:
            const VisualDensity(vertical: -4),
            leading: const Icon(Icons.book),
            title: const Text('Terms and Conditions'),
            titleTextStyle: const TextStyle(fontSize: 13),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const QRScanPage(),
                ),
              );
            },
          ),
          ListTile(
            visualDensity:
            const VisualDensity(vertical: -4),
            leading:
            const Icon(Icons.help_center_rounded),
            title: const Text('About PARA!'),
            titleTextStyle: const TextStyle(fontSize: 13),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const QRScanPage(),
                ),
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
              child: _buildJeepneySuggestionList(),
            ),
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
      ) {
    if (userLoc != null && _userLoc == null) {
      _userLoc = userLoc;
    }

    _updatePolyline();

    return Stack(
      children: [
        // Optional hint BEFORE destination is set
        if (_showHint && _isLocationInitialized && !_hasSetDestination)
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 24.0),
              child: _buildInfoCard(
                'Tap on the map to set your destination and see jeepneys on your route.',
              ),
            ),
          ),

        // Top destination bar (same as before)
        _buildDestinationBar(),

        // Ads button (same as before)
        _buildCompactAdsButton(),

        // NEW: bottom popup with jeep list + destination info + PARA button
        _buildDestinationSheet(),
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
      externalPolylinesBuilder: () => _polylines,
    );
  }

  // 🔵 Road-following route polyline via Google Directions API
  Future<void> _buildRoutePolyline() async {
    if (_userLoc == null || _destination == null) {
      debugPrint('buildRoutePolyline: userLoc or destination is null');
      return;
    }

    _polylines.removeWhere(
          (p) => p.polylineId.value == 'destinationRoute',
    );

    final origin =
    PointLatLng(_userLoc!.latitude, _userLoc!.longitude);
    final dest =
    PointLatLng(_destination!.latitude, _destination!.longitude);

    debugPrint('buildRoutePolyline: requesting route $origin -> $dest');

    final result = await _polylinePoints.getRouteBetweenCoordinates(
      googleApiKey: _googleApiKey, // ✅ correct param for v2.1.0
      request: PolylineRequest(
        origin: origin,
        destination: dest,
        mode: TravelMode.driving,
        avoidHighways: false,
        avoidTolls: false,
      ),
    );

    if (result.points.isEmpty) {
      debugPrint('buildRoutePolyline: no points from Directions API');
      return;
    }

    final routePoints = result.points
        .map((p) => LatLng(p.latitude, p.longitude))
        .toList();

    setState(() {
      _polylines.add(Polyline(
        polylineId: const PolylineId('destinationRoute'),
        color: Colors.blue,
        width: 5,
        points: routePoints,
      ));
    });
    debugPrint('buildRoutePolyline: route has ${routePoints.length} points');
  }
}
