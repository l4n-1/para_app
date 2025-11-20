import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:para2/services/RealtimeDatabaseService.dart';
import 'package:para2/pages/settings/profile_settings.dart';
// math import removed — bearing/rotation calculations are not used
import 'package:para2/theme/app_icons.dart';
import 'package:para2/services/location_service.dart';
import 'package:para2/pages/settings/PHdashboard.dart';
import 'package:provider/provider.dart';
// map theme applied via MapControllerService when controller is set
import 'package:para2/services/map_controller_service.dart';
import 'package:para2/services/button_actions.dart';
import 'package:para2/services/follow_service.dart';
import 'package:para2/services/snackbar_service.dart';
import 'package:para2/services/location_broadcast.dart';

class SharedHome extends StatefulWidget {
  final String roleLabel;
  final VoidCallback onSignOut;
  final List<Widget> roleMenu;
  final Widget Function(
      BuildContext context,
      String displayName,
      LatLng? userLoc,
      void Function(LatLng position) onMapTap,
      )
  roleContentBuilder;
  final void Function(LatLng position)? onMapTap;

  const SharedHome({
    super.key,
    required this.roleLabel,
    required this.onSignOut,
    required this.roleMenu,
    required this.roleContentBuilder,
    this.onMapTap,
  });

  static _SharedHomeState? of(BuildContext context) =>
      context.findAncestorStateOfType<_SharedHomeState>();

  @override
  State<SharedHome> createState() => _SharedHomeState();
}

class _SharedHomeState extends State<SharedHome> with TickerProviderStateMixin {
  final Completer<GoogleMapController> _mapController = Completer();
  final RealtimeDatabaseService _rtdbService = RealtimeDatabaseService();

  final Map<MarkerId, Marker> _markers = {};
  final Map<String, Marker> _jeepMarkers = {};
  final Map<PolylineId, Polyline> _polylines = {};

  StreamSubscription? _devicesSub;

  bool _isMapReady = false;
  bool _hasCenteredOnUser = false;
  LatLng? _currentUserLoc;
  bool _isFirstLocation = true;

  bool _isPanelOpen = false;
  late final AnimationController _panelController;
  late final Animation<Offset> _panelOffset;

  String _displayName = 'User';
  bool _isProfileIncomplete = false;
  bool _featuresLocked = false;

  // Zoom tracking
  double _currentZoom = 14.0;

  // Animation controllers for smooth marker movement (uses vsync)
  final Map<MarkerId, AnimationController> _markerAnimControllers = {};

  // Throttle camera updates to avoid jerky camera movement
  DateTime? _lastCameraUpdate;

  // User coins
  double _userCoins = 0.0;

  // default initial camera (used until we resolve a last-known location)
  CameraPosition _initialCamera = const CameraPosition(
    target: LatLng(14.8528, 120.8180),
    zoom: 14,
  );

  /// Whether we've already centered the camera to the user's live location
  /// after it became available. Used to avoid recentering on every update.

  @override
  void initState() {
    super.initState();
    _panelController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _panelOffset =
        Tween<Offset>(begin: const Offset(-1.0, 0.0), end: Offset.zero).animate(
          CurvedAnimation(parent: _panelController, curve: Curves.easeInOut),
        );

    _loadCustomMarkers();
    // Try to set an initial camera from a cached "last known" location
    _applyLastKnownLocationToInitialCamera();
    _subscribeDevicesRealtime();
    _checkProfileCompletion();
    _loadUserDisplayName();
    _loadUserCoins();

    // Subscribe to app-wide location broadcasts so this SharedHome instance
    // receives live location updates even if callers can't find the ancestor.
    LocationBroadcast.instance.stream.listen((loc) {
      debugPrint('LocationBroadcast -> SharedHome: $loc');
      updateUserLocation(loc);
    }, onError: (e) {
      debugPrint('LocationBroadcast error: $e');
    });

    // ✅ ADD: Get initial location
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _getCurrentLocation();
    });
  }

  Future<void> _applyLastKnownLocationToInitialCamera() async {
    try {
      final last = await LocationService.getLastKnownLocation();
      if (last != null) {
        setState(() {
          _initialCamera = CameraPosition(target: last, zoom: 14);
        });
        debugPrint('Using last known location for initial camera: $last');
      }
    } catch (e) {
      debugPrint('Error getting last known location: $e');
    }
  }

  Future<void> _loadCustomMarkers() async {
    try {
      // Load user directional marker
      _userDirectionalIcon = AppIcons.userPin;
    } catch (e) {
      debugPrint('Error loading custom markers: $e');
      // Fallback to default markers
      _userDirectionalIcon = AppIcons.userPin;
    }
  }

  Future<void> _loadUserDisplayName() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (doc.exists) {
        final data = doc.data()!;

        // ✅ FIXED: Format as "FirstName L." (Last Name Initial)
        String formattedName = 'User';

        final firstName = data['firstName']?.toString() ?? '';
        final lastName = data['lastName']?.toString() ?? '';

        if (firstName.isNotEmpty && lastName.isNotEmpty) {
          formattedName = '$firstName ${lastName[0]}.';
        } else if (firstName.isNotEmpty) {
          formattedName = firstName;
        } else if (user.displayName != null) {
          final nameParts = user.displayName!.split(' ');
          if (nameParts.length >= 2) {
            formattedName = '${nameParts[0]} ${nameParts[1][0]}.';
          } else {
            formattedName = user.displayName!;
          }
        } else if (user.email != null) {
          formattedName = user.email!.split('@').first;
        }

        setState(() {
          _displayName = formattedName;
        });
      }
    } catch (e) {
      debugPrint('Error loading user name: $e');
    }
  }



  // ✅ ADD: Load user coins from Firestore
  Future<void> _loadUserCoins() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (doc.exists) {
        final data = doc.data()!;
        final coins = (data['coins'] as num?)?.toDouble() ?? 0.0;
        setState(() {
          _userCoins = coins;
        });
      }
    } catch (e) {
      debugPrint('Error loading user coins: $e');
    }
  }

  Future<void> _checkProfileCompletion() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
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

  // Listen to camera movements to update zoom and markers
  void _onCameraMove(CameraPosition position) {
    setState(() {
      _currentZoom = position.zoom;
    });
    _updateJeepMarkersWithZoom(); // Update markers with new zoom
  }

  void _updateJeepMarkersWithZoom() {
    // Update all jeep markers with appropriate icon size
    _jeepMarkers.forEach((id, marker) {
      final newMarker = marker.copyWith(
        iconParam: AppIcons.getJeepIconForZoom(_currentZoom),
      );
      _jeepMarkers[id] = newMarker;
    });

    // Update tsuperhero jeep marker if exists
    if (_markers.containsKey(const MarkerId('tsuperhero_jeep'))) {
      final existingMarker = _markers[const MarkerId('tsuperhero_jeep')]!;
      final updatedMarker = existingMarker.copyWith(
        iconParam: AppIcons.getJeepIconForZoom(_currentZoom),
      );
      addOrUpdateMarker(const MarkerId('tsuperhero_jeep'), updatedMarker);
    }

    setState(() {}); // Refresh UI
  }

  Future<void> centerOnJeepMarker() async {
    if (!_isMapReady || _jeepMarkers.isEmpty) return;

    final firstJeep = _jeepMarkers.values.first;
    final ctrl = await _mapController.future;
    ctrl.animateCamera(CameraUpdate.newLatLngZoom(firstJeep.position, 16));
  }

  void addOrUpdateMarker(MarkerId id, Marker marker) {
    setState(() {
      _markers[id] = marker;
    });
  }

  void removeMarker(MarkerId id) {
    setState(() {
      _markers.remove(id);
    });
  }

  void clearExternalPolylines() {
    setState(() => _polylines.clear());
  }

  void setExternalPolylines(Set<Polyline> lines) {
    setState(() {
      _polylines
        ..clear()
        ..addEntries(lines.map((l) => MapEntry(l.polylineId, l)));
    });
  }

  Future<GoogleMapController> getMapController() async => _mapController.future;

  // ✅ FIXED: Enhanced location update with custom user marker
  Future<void> updateUserLocation(LatLng userLoc) async {
    if (userLoc.latitude == 0.0 && userLoc.longitude == 0.0) {
      debugPrint("⚠️ Invalid location (0,0) - skipping");
      return;
    }

    setState(() {
      _currentUserLoc = userLoc;
    });

    final recvTs = DateTime.now().millisecondsSinceEpoch;
    debugPrint("📍 SharedHome received location: $userLoc (recv_ts=$recvTs)");

    // Smoothly animate the user marker from its previous position to the
    // new position so movement looks smooth instead of jumping in big steps.
    final markerId = const MarkerId('user_marker');
    final prev = _markers[markerId];
    final from = prev?.position ?? userLoc;

    _animateMarkerMove(markerId, from, userLoc);

    // If follow mode is enabled, animate the camera to the user's position
    // on each live update. Otherwise, only center once if we haven't yet
    // (preserving previous behavior but respecting follow toggle).
    final follow = FollowService.instance.isFollowing.value;
    if (_isMapReady) {
      try {
        final ctrl = await _mapController.future;
        final now = DateTime.now();
        // Only update camera position at most twice per second to avoid
        // excessive camera jumps while still keeping it responsive.
        if (follow) {
          if (_lastCameraUpdate == null || now.difference(_lastCameraUpdate!).inMilliseconds > 333) {
            await ctrl.animateCamera(CameraUpdate.newLatLng(userLoc));
            _lastCameraUpdate = now;
          }
        } else {
          if (!_hasCenteredOnUser) {
            await ctrl.animateCamera(CameraUpdate.newLatLngZoom(userLoc, 16.0));
            _hasCenteredOnUser = true;
          }
        }
      } catch (e) {
        debugPrint('Error centering to user location: $e');
      }
    }
  }

  // Smoothly animate a marker from `from` -> `to` by updating the marker
  // position in small steps. Cancels any existing animation for the same id.
  void _animateMarkerMove(MarkerId id, LatLng from, LatLng to, {int durationMs = 240}) {
    // Cancel any existing animation controller for this marker
    final existing = _markerAnimControllers.remove(id);
    existing?.stop();
    existing?.dispose();

    if (from.latitude == to.latitude && from.longitude == to.longitude) {
      // No movement — just set marker once
      final m = Marker(
        markerId: id,
        position: to,
        icon: _userDirectionalIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        infoWindow: const InfoWindow(title: 'Your Location'),
        anchor: const Offset(0.5, 0.9),
        flat: true,
      );
      addOrUpdateMarker(id, m);
      return;
    }

    final controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: durationMs),
    );
    final animation = CurvedAnimation(parent: controller, curve: Curves.linear);

    animation.addListener(() {
      final frac = animation.value.clamp(0.0, 1.0);
      final lat = from.latitude + (to.latitude - from.latitude) * frac;
      final lng = from.longitude + (to.longitude - from.longitude) * frac;

      final m = Marker(
        markerId: id,
        position: LatLng(lat, lng),
        icon: _userDirectionalIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        infoWindow: const InfoWindow(title: 'Your Location'),
        anchor: const Offset(0.5, 0.9),
        flat: true,
      );
      addOrUpdateMarker(id, m);
    });

    controller.addStatusListener((status) {
      if (status == AnimationStatus.completed || status == AnimationStatus.dismissed) {
        // Cleanup
        controller.stop();
        controller.dispose();
        _markerAnimControllers.remove(id);
      }
    });

    _markerAnimControllers[id] = controller;
    controller.forward();
  }

  // Bearing calculations removed — user marker remains static (no rotation).

  // (Helper methods removed) — marker management handled via
  // `addOrUpdateMarker` / `removeMarker` and map controller via
  // `_mapController` completer directly.

  void _subscribeDevicesRealtime() {
    final ref = _rtdbService.devicesRef;
    _devicesSub = ref.onValue.listen((event) {
      final snapshot = event.snapshot;
      if (!snapshot.exists || snapshot.value == null) return;

      final raw = snapshot.value;
      if (raw is! Map) return;

      final devices = raw.cast<dynamic, dynamic>();
      devices.forEach((id, rawDevice) {
        if (rawDevice is Map) {
          final lat = double.tryParse(
            rawDevice['latitude']?.toString() ??
                rawDevice['lat']?.toString() ??
                '',
          );
          final lng = double.tryParse(
            rawDevice['longitude']?.toString() ??
                rawDevice['lng']?.toString() ??
                '',
          );
          final speed = double.tryParse(
            rawDevice['speed_kmh']?.toString() ??
                rawDevice['speed']?.toString() ??
                '0',
          );
          final course = double.tryParse(
            rawDevice['course']?.toString() ?? '0',
          );

          if (lat != null && lng != null) {
            final currentPassengers = (rawDevice['currentPassengers'] as int?) ?? 0;
            final maxCapacity = (rawDevice['maxCapacity'] as int?) ?? 22;

            final marker = Marker(
              markerId: MarkerId('jeep_$id'),
              position: LatLng(lat, lng),
              rotation: course ?? 0,
              anchor: const Offset(0.5, 0.5),
              icon: AppIcons.getJeepIconForZoom(_currentZoom),
              infoWindow: InfoWindow(
                title: 'Jeep #${_extractDeviceNumber(id.toString())} | ${(speed ?? 0).toStringAsFixed(0)} kph',
                snippet: 'Capacity: $currentPassengers/$maxCapacity',
              ),
            );
            _jeepMarkers[id.toString()] = marker;
          }
        }
      });

      setState(() {});
    },
        onError: (err) {
          debugPrint("RTDB devices subscription error: $err");
        });
  }

  // Extract device number from ID (ESPTRACKER001 -> 1, ESPTRACKER002 -> 2, etc.)
  int _extractDeviceNumber(String deviceId) {
    try {
      // Remove non-digit characters and parse the number
      final numberString = deviceId.replaceAll(RegExp(r'[^0-9]'), '');
      return int.tryParse(numberString) ?? 1;
    } catch (e) {
      return 1;
    }
  }

  Set<Marker> _getRoleSpecificMarkers() {
    final markers = <Marker>{};

    markers.addAll(_jeepMarkers.values);
    markers.addAll(_markers.values);

    return markers;
  }

  void _togglePanel() {
    setState(() {
      _isPanelOpen = !_isPanelOpen;
      _isPanelOpen ? _panelController.forward() : _panelController.reverse();
    });
  }

  @override
  void dispose() {
    _devicesSub?.cancel();
    _panelController.dispose();
    // Dispose any active marker animation controllers
    for (final c in _markerAnimControllers.values) {
      try {
        c.stop();
        c.dispose();
      } catch (_) {}
    }
    _markerAnimControllers.clear();
    super.dispose();
  }

  Future<void> centerMap(LatLng pos) async {
    if (!_isMapReady) return;
    final ctrl = await _mapController.future;
    ctrl.animateCamera(CameraUpdate.newLatLngZoom(pos, 16));
  }

  // ✅ ADD: Get current location manually
  Future<void> _getCurrentLocation() async {
    try {
      final LatLng? location = await LocationService.getCurrentLocation();

      if (location != null) {
        setState(() {
          _currentUserLoc = location;
        });
        updateUserLocation(location);
        debugPrint("📍 Manual location fetched: $location");
      } else {
        debugPrint("❌ Could not get location - permissions issue?");
      }
    } catch (e) {
      debugPrint("❌ Location error: $e");
    }
  }

  // ✅ FIXED: Recenter button function with location fallback
  Future<void> _centerOnUser() async {
    try {
      if (!_isMapReady) {
        debugPrint("❌ Map not ready yet");
        return;
      }

      final GoogleMapController controller = await _mapController.future;

      // If no location, try to get it first
        if (_currentUserLoc == null) {
        SnackbarService.show(context, 'Getting your location...', duration: const Duration(seconds: 2));
        
        
        
        
        await _getCurrentLocation();

        // Check again after trying to get location
        if (_currentUserLoc == null) {
          SnackbarService.show(context, 'Cannot get location. Check permissions and try again.', duration: const Duration(seconds: 3));
          return;
        }
      }

      debugPrint("📍 Centering to: $_currentUserLoc");

      await controller.animateCamera(
        CameraUpdate.newLatLngZoom(_currentUserLoc!, 16.0),
      );

      SnackbarService.show(context, 'Centered on your location', duration: const Duration(seconds: 1));

    } catch (e) {
      debugPrint("Recenter error: $e");
      SnackbarService.show(context, 'Failed to center map', duration: const Duration(seconds: 2));
    }
  }

  // ✅ UPDATED: Trophy button function with coins display and new button texts
  void _showCoinsDialog() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          padding: const EdgeInsets.all(20),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.85,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Para! Coins',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                  color: Colors.blue,
                ),
              ),
              const SizedBox(height: 8),
              // ✅ ADDED: Current coins display
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Para! Coins: ${_userCoins.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Choose an option to get Para! Coins:',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 20),
              // ✅ CHANGED: Buy Coins using online currency button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    _showBuyCoinsScreen();
                  },
                  child: const Text(
                    'Buy Coins using Online Currency',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // ✅ CHANGED: Watch ads to get coins button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    _showAdWatchScreen();
                  },
                  child: const Text(
                    'Watch Ads to Get Coins',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ✅ ADDED: Buy coins screen
  void _showBuyCoinsScreen() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Buy Para! Coins'),
        content: const Text('Online payment screen will be implemented here. Purchase coins using credit/debit cards, e-wallets, or other payment methods.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showAdWatchScreen() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Watch Ads to Earn Coins'),
        content: const Text('Ad watching functionality will be implemented here. Earn coins by watching ads.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final panelWidth = MediaQuery.of(context).size.width * 0.7;
    
    return Scaffold(
  body: SizedBox.expand( // <-- forces Stack to fill entire screen
    child: Stack(
      children: [
        // Main Map (rebuilds when follow mode toggles so we can enable/disable gestures)
        ValueListenableBuilder<bool>(
          valueListenable: FollowService.instance.isFollowing,
          builder: (context, following, _) {
            return Positioned.fill(
              child: GoogleMap(
                initialCameraPosition: _initialCamera,
                myLocationEnabled: false, //set to true if pasahero loc does not work
                myLocationButtonEnabled: false, // Disable default button
                zoomControlsEnabled: false,
                // When following, prevent user panning/rotating/tilting so camera stays on user.
                scrollGesturesEnabled: !following,
                rotateGesturesEnabled: !following,
                tiltGesturesEnabled: !following,
                // Keep zoom enabled so user can zoom even while following.
                zoomGesturesEnabled: true,
                markers: _getRoleSpecificMarkers(),
                polylines: _polylines.values.toSet(),
                onMapCreated: (controller) async {
                  if (!_mapController.isCompleted) {
                    _mapController.complete(controller);
                  }
                  setState(() => _isMapReady = true);
                  debugPrint("✅ Map controller is ready");
                  // Set the global controller so other parts of the app can access it
                  await MapControllerService.instance.setController(controller);
                  // If we already have a user location from before the map was ready,
                  // center the camera now (only once).
                  if (_currentUserLoc != null && !_hasCenteredOnUser) {
                    try {
                      await controller.animateCamera(
                        CameraUpdate.newLatLngZoom(_currentUserLoc!, 16.0),
                      );
                      _hasCenteredOnUser = true;
                    } catch (e) {
                      debugPrint('Error centering on map created: $e');
                    }
                  }
                },
                onTap: widget.onMapTap,
                onCameraMove: _onCameraMove,
              ),
            );
          },
        ),

        // Profile incomplete warning
        if (_isProfileIncomplete)
          Positioned(
            top: 80,
            left: 0,
            right: 0,
            child: Container(
              color: Colors.amber.withOpacity(0.95),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      "⚠️Please complete your profile to unlock all features.",
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const ProfileSettingsPage()),
                      ).then((_) => _checkProfileCompletion());
                    },
                    child: const Text(
                      "Complete Now",
                      style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          ),

        // Top app bar
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              child: Row(
                children: [ 
                  Column(
                    children: [
                  GestureDetector(
                    onTap: _togglePanel,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color.fromARGB(255, 16, 16, 36),
                        borderRadius: BorderRadius.circular(8),
                        
                      ),
                      child: Column(
                        children: [
                          const SizedBox(width: 8),
                          Text(
                            
                            _displayName,
                            style: TextStyle(
                              height: 1,
                              color:Color.fromARGB(255, 196, 196, 196), fontWeight: FontWeight.bold, fontSize: 18,fontFamily: GoogleFonts.inter().fontFamily),
                          ),
                          Text( 
                            widget.roleLabel,
                            style: TextStyle(
                              height: 1,
                              color: Colors.white.withOpacity(0.7),
                              fontSize: 8.5,
                              fontFamily: GoogleFonts.inter().fontFamily,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Text('PROFILE ••• ',
                      style: TextStyle(
                        height: 1,
                        fontSize: 12,
                        color: const Color.fromARGB(255, 0, 0, 0).withOpacity(0.6),
                        fontFamily: GoogleFonts.roboto().fontFamily,
                        fontWeight: FontWeight.w900,
                      ),
                      ),
                    ],
                  )
                    ],
                  ),


                  const Spacer(),
                  Text(
                    "PARA!",
                    style: TextStyle(
                      fontStyle: FontStyle.italic,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: const Color.fromARGB(150, 255, 255, 255),
                      shadows: [Shadow(color: Colors.black.withOpacity(1.0), blurRadius: 20)],
                    ),
                  ),
                ],
              
              ),
            ),
          ),
        ),

        // Action buttons - UPPER RIGHT (coins, center, theme, follow)
        Positioned(
          top: 100,
          right: 16,
          child: Column(
            children: [
              FloatingActionButton(
                mini: true,
                backgroundColor: const Color.fromARGB(255, 193, 212, 16),
                onPressed: _showCoinsDialog,
                child: const Icon(Icons.monetization_on, color: Color.fromARGB(255, 28, 23, 46), size: 20),
              ),
              const SizedBox(height: 8),
              FloatingActionButton(
                mini: true,
                backgroundColor: const Color.fromARGB(255, 28, 23, 46),
                onPressed: _centerOnUser,
                child: const Icon(Icons.my_location, color: Color.fromARGB(255, 124, 155, 53), size: 20),
              ),
              const SizedBox(height: 8),
              // Theme toggle
              FloatingActionButton(
                mini: true,
                backgroundColor: const Color.fromARGB(255, 28, 23, 46),
                onPressed: () => ButtonActions.toggleMapTheme(context, null),
                child: const Icon(Icons.brightness_6, color:Color.fromARGB(255, 124, 155, 53), size: 20),
              ),
              const SizedBox(height: 8),
              // Follow toggle
              ValueListenableBuilder<bool>(
                valueListenable: FollowService.instance.isFollowing,
                builder: (context, following, _) {
                  return FloatingActionButton(
                    mini: true,
                    backgroundColor: const Color.fromARGB(255, 28, 23, 46),
                    onPressed: () => ButtonActions.toggleFollowMode(context),
                    child: Icon(
                      following ? Icons.gps_fixed : Icons.gps_not_fixed,
                      color: Color.fromARGB(255, 124, 155, 53),
                      size: 20,
                    ),
                  );
                },
              ),
            ],
          ),
        ),

        // Bottom content
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: widget.roleContentBuilder(
            context,
            _displayName,
            _currentUserLoc,
            widget.onMapTap ?? (_) {},
          ),
        ),

        // Side panel overlay
        if (_isPanelOpen)
          Positioned.fill(
            child: GestureDetector(
              onTap: _togglePanel,
              child: Container(color: Colors.black.withOpacity(0.35)),
            ),
          ),

        // Side panel
        Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: panelWidth,
            child: SlideTransition(
              position: _panelOffset,
              child: _buildSidePanel(context),
            ),
          ),
        ),
      ],
    ),
  ),
);

  }

  Widget _buildSidePanel(BuildContext context)
  
  {
    return SafeArea(
      child: 
      Stack(
      children: [
      Container(
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.bottomCenter,
            radius: 5,
            colors: [ 
              const Color.fromARGB(255, 4, 3, 5),
              const Color.fromARGB(255, 62, 60, 68),
            ],),
            color: Colors.black.withOpacity(0.98),
          borderRadius: const BorderRadius.only(
            topRight: Radius.circular(35),
            bottomRight: Radius.circular(35),
          ),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10),
          ],
        ),

        child: SingleChildScrollView(
          child: Column(
            children: [
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PHDashboard(displayName: _displayName),
                    ),
                  );
                },
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(

                    colors: const [
                      Color.fromARGB(255, 28, 19, 110), // very dark purple
                      Color.fromARGB(255, 66, 19, 80), // rich violet
                      Color.fromARGB(255, 64, 27, 95), // warm indigo
                      Color.fromARGB(255, 35, 34, 129), // lighter purple
                    ],

                    tileMode: TileMode.clamp,
                  ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 10,
                        spreadRadius: 2.5,
                        offset: const Offset(0, 8),
                      ),
                    ],
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(35),
                      
                    ),
                    color: const Color.fromARGB(255, 49, 8, 126),
                  ),
                  padding: const EdgeInsets.only(
                    top: 10,
                    bottom: 10,
                    left: 10,
                    right: 40,
                  ),
                  
                
                  child: 
                  Container(
                    padding: const EdgeInsets.all(7.5),
                    decoration: BoxDecoration(
                      gradient: RadialGradient(colors:  [
                        Color.fromARGB(255, 0, 0, 0),
                        Color.fromARGB(255, 28, 26, 32),
                      ],
                      center: Alignment.centerLeft,
                      radius: 3.0,
                      ),

                      borderRadius: BorderRadius.only(
                        topRight: Radius.circular(30),
                        bottomRight: Radius.circular(30),
                        topLeft: Radius.circular(35),
                        bottomLeft: Radius.circular(35),
                      ),
                    ),
                    child:
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 28,
                          backgroundColor: Colors.grey[400],
                          child: Icon(
                            widget.roleLabel == 'TSUPERHERO'
                                ? Icons.directions_bus
                                : Icons.person,
                            color: Colors.white,
                            size: 32,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _displayName,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Colors.white
                              ),
                            ),

                            Text(
                              widget.roleLabel,
                              style: const TextStyle(
                                color: Color.fromARGB(255, 255, 255, 255),
                                fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(width: 40),
                      Container(
                        padding: EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Color.fromARGB(122, 197, 197, 197),
                          borderRadius: BorderRadius.circular(25),
                        ) ,
                      child: Icon(
                        Icons.arrow_forward_ios,
                        size: 16,
                        color: Color.fromARGB(255, 0, 0, 0),
                        ),
                      ),
                    ],
                  ),),
                ),
              ),

            // Map control buttons (recenter, theme toggle, follow toggle, etc.)
            SizedBox(height: 10),
              ...widget.roleMenu,
  Container(
    margin: const EdgeInsets.only(right: 140,top: 15),
    decoration: 
    BoxDecoration(
      boxShadow: [BoxShadow(
        color: Colors.black.withOpacity(0.3),
        blurRadius: 10,
        offset: const Offset(0, 0),
      ),],
      gradient: const RadialGradient(
        center: Alignment.centerLeft,
        radius: 2.8,
        colors: [
         Color.fromARGB(255, 30, 30, 36),
           Color.fromARGB(255, 43, 48, 51),
        ],
      ),
      borderRadius: const BorderRadius.only(
        topRight: Radius.circular(10),
        bottomRight: Radius.circular(10),
      ),
    ),
    child: ListTile(
      visualDensity: VisualDensity.compact,
      leading: const Icon(Icons.logout),
      iconColor: Color.fromARGB(255, 255, 255, 255),
      title: const Text('Log out'),
      onTap: widget.onSignOut,
    ),
  ),
  SizedBox(height: 20),
              const SizedBox(height: 10,),
              const Divider(),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: Column(
                  children: [
                    
                    Image.asset('assets/Paralogotemp.png', height: 68),
                    const Text(
                      'PARA! - Transport App',
                      style: TextStyle(color: Color.fromARGB(192, 255, 255, 255)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      
      ],
      ),
    
    );  
  }

  // Add missing variable declaration
  BitmapDescriptor? _userDirectionalIcon;
}