import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:para2/services/RealtimeDatabaseService.dart';
import 'package:para2/pages/settings/profile_settings.dart';
import 'dart:math' as math;
import 'package:para2/theme/app_icons.dart';

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
  LatLng? _currentUserLoc;
  bool _hasCenteredOnUser = false;
  bool _isFirstLocation = true;

  bool _isPanelOpen = false;
  late final AnimationController _panelController;
  late final Animation<Offset> _panelOffset;

  String _displayName = 'User';
  bool _isProfileIncomplete = false;
  bool _featuresLocked = false;

  // Zoom tracking
  double _currentZoom = 14.0;

  static const CameraPosition _initialCamera = CameraPosition(
    target: LatLng(14.8528, 120.8180),
    zoom: 14,
  );

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
    _subscribeDevicesRealtime();
    _checkProfileCompletion();
    _loadUserDisplayName();
  }

  Future<void> _loadCustomMarkers() async {
    try {
      // Load user directional marker
      _userDirectionalIcon = await BitmapDescriptor.fromAssetImage(
        const ImageConfiguration(size: Size(48, 48)),
        'assets/USERPIN.png',
      );
    } catch (e) {
      debugPrint('Error loading custom markers: $e');
      // Fallback to default markers
      _userDirectionalIcon = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue);
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
  void updateUserLocation(LatLng userLoc) {
    if (userLoc.latitude == 0.0 && userLoc.longitude == 0.0) {
      debugPrint("⚠️ Invalid location (0,0) - skipping");
      return;
    }

    setState(() {
      _currentUserLoc = userLoc;
    });

    debugPrint("📍 SharedHome received location: $userLoc");

    // Update user marker with custom directional icon
    final userMarker = Marker(
      markerId: const MarkerId('user_marker'),
      position: userLoc,
      icon: _userDirectionalIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
      infoWindow: const InfoWindow(title: 'Your Location'),
      anchor: const Offset(0.5, 0.5),
      flat: true,
    );

    addOrUpdateMarker(const MarkerId('user_marker'), userMarker);
  }

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
    super.dispose();
  }

  Future<void> centerMap(LatLng pos) async {
    if (!_isMapReady) return;
    final ctrl = await _mapController.future;
    ctrl.animateCamera(CameraUpdate.newLatLngZoom(pos, 16));
  }

  // ✅ FIXED: Recenter button function
  Future<void> _centerOnUser() async {
    try {
      // Get the map controller
      final GoogleMapController controller = await _mapController.future;

      // Check if we have a current location
      if (_currentUserLoc == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('📍 Waiting for your location...'),
            duration: Duration(seconds: 2),
          ),
        );
        return;
      }

      // Center on user location with zoom
      await controller.animateCamera(
        CameraUpdate.newLatLngZoom(_currentUserLoc!, 16.0),
      );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('📍 Centered on your location'),
          duration: Duration(seconds: 1),
        ),
      );

    } catch (e) {
      debugPrint("❌ Recenter error: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Failed to center: $e'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  // ✅ FIXED: Trophy button function with two options
  void _showCoinsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          'Para! Coins',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.blue,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Choose an option to get Para! Coins:',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            // Pay using Para! Coins button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () {
                  Navigator.pop(context);
                  _showPaymentScreen();
                },
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.payment, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Pay using Para! Coins',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Watch ads button
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
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.play_arrow, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Watch ads to get Para! Coins',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showPaymentScreen() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pay using Para! Coins'),
        content: const Text('Payment screen will be implemented here. Users can use their coins for payments.'),
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
      body: Stack(
        children: [
          // Main Map
          Positioned.fill(
            child: GoogleMap(
              initialCameraPosition: _initialCamera,
              myLocationEnabled: true,
              myLocationButtonEnabled: false, // Disable default button
              zoomControlsEnabled: false,
              markers: _getRoleSpecificMarkers(),
              polylines: _polylines.values.toSet(),
              onMapCreated: (controller) {
                if (!_mapController.isCompleted) {
                  _mapController.complete(controller);
                }
                setState(() => _isMapReady = true);
              },
              onTap: widget.onMapTap,
              onCameraMove: _onCameraMove,
            ),
          ),

          // Profile incomplete warning
          if (_isProfileIncomplete)
            Positioned(
              top: 80,
              left: 0,
              right: 0,
              child: Container(
                color: Colors.amber.withOpacity(0.95),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        "⚠️ Please complete your profile to unlock all features.",
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ProfileSettingsPage(),
                          ),
                        ).then((_) => _checkProfileCompletion());
                      },
                      child: const Text(
                        "Complete Now",
                        style: TextStyle(
                          color: Colors.blueAccent,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Top app bar
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: _togglePanel,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 5,
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Icon(
                            widget.roleLabel == 'TSUPERHERO'
                                ? Icons.directions_bus
                                : Icons.person,
                            size: 18,
                            color: Colors.black54,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _displayName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Spacer(),
                  const Text(
                    "PARA!",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: Colors.white,
                      shadows: [Shadow(color: Colors.black38, blurRadius: 4)],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ✅ FIXED: Trophy button - UPPER RIGHT
          Positioned(
            top: 100,
            right: 16,
            child: FloatingActionButton(
              mini: true,
              backgroundColor: Colors.amber,
              onPressed: _showCoinsDialog,
              child: const Icon(Icons.monetization_on, color: Colors.white, size: 20),
            ),
          ),

          // ✅ FIXED: Recenter button - UPPER RIGHT (left of trophy)
          Positioned(
            top: 100,
            right: 70,
            child: FloatingActionButton(
              mini: true,
              backgroundColor: Colors.white,
              onPressed: _centerOnUser,
              child: const Icon(Icons.my_location, color: Colors.blue, size: 20),
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
    );
  }

  Widget _buildSidePanel(BuildContext context) {
    return SafeArea(
      child: Container(
        height: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white,
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
              Container(
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(35),
                    bottomRight: Radius.circular(25),
                  ),
                  color: Colors.grey[100],
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 20,
                ),

                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: Colors.grey[400],
                      child: Icon(
                        widget.roleLabel == 'TSUPERHERO'
                            ? Icons.directions_bus
                            : Icons.person,
                        color: Colors.white,
                        size: 28,
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
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.roleLabel,
                          style: const TextStyle(
                            color: Colors.black54,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              ...widget.roleMenu,
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('Log out'),
                onTap: widget.onSignOut,
              ),
              const Divider(),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: Column(
                  children: [
                    Image.asset('assets/Paralogotemp.png', height: 48),
                    const SizedBox(height: 8),
                    const Text(
                      'PARA! - Transport App',
                      style: TextStyle(color: Colors.black54),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Add missing variable declaration
  BitmapDescriptor? _userDirectionalIcon;
}