// lib/pages/pasahero_home.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:para2/pages/login.dart';

class PasaheroHome extends StatefulWidget {
  const PasaheroHome({super.key});

  @override
  State<PasaheroHome> createState() => _PasaheroHomeState();
}

class _PasaheroHomeState extends State<PasaheroHome>
    with TickerProviderStateMixin {
  // Map & location
  final Completer<GoogleMapController> _mapController = Completer();
  final Map<MarkerId, Marker> _markers = {};
  StreamSubscription<Position>? _positionSub;
  bool _mapReady = false;

  // Panel state & animation
  bool _isPanelOpen = false;
  late final AnimationController _panelController;
  late final Animation<Offset> _panelOffset;
  static const Duration _panelAnimDuration = Duration(milliseconds: 300);

  // Display name (from Firestore)
  String _displayName = 'Username';

  // Toggle for emulator convenience: disable location streaming if emulator is unstable
  bool _enableLocationStream = true;

  // Firebase
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Initial camera (Manila fallback)
  static const CameraPosition _initialCamera = CameraPosition(
    target: LatLng(14.5995, 120.9842),
    zoom: 14,
  );

  @override
  void initState() {
    super.initState();

    // Panel animation setup
    _panelController = AnimationController(
      vsync: this,
      duration: _panelAnimDuration,
    );
    _panelOffset = Tween<Offset>(
      begin: const Offset(-1.0, 0.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _panelController, curve: Curves.easeInOut));

    // Start tasks
    _initLocationAndMap();
    _loadDisplayName();
  }

  Future<void> _loadDisplayName() async {
    final user = _auth.currentUser;
    if (user == null) return;
    try {
      final doc = await _firestore.collection('users').doc(user.uid).get();
      if (doc.exists) {
        final data = doc.data();
        if (data != null) {
          final role = (data['role'] ?? 'pasahero').toString().toLowerCase();
          if (role == 'pasahero') {
            setState(() {
              _displayName = (data['userName'] ?? 'Username') as String;
            });
          } else if (role == 'tsuperhero') {
            setState(() {
              _displayName = (data['plateNumber'] ?? 'DRVR XXX') as String;
            });
          } else {
            setState(() {
              _displayName = (data['userName'] ?? 'Username') as String;
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Failed to load display name: $e');
    }
  }

  Future<void> _initLocationAndMap() async {
    // Permission check
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever ||
          permission == LocationPermission.denied) {
        debugPrint('Location permission denied. Skipping location streaming.');
        return;
      }
    } catch (e) {
      debugPrint('Error checking/requesting location permission: $e');
      return;
    }

    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 5,
    );

    // Try to get initial position
    try {
      Position pos;
      try {
        pos = await Geolocator.getCurrentPosition(
          locationSettings: locationSettings,
        );
      } catch (_) {
        pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.best,
        );
      }
      _updateUserLocation(LatLng(pos.latitude, pos.longitude));
      if (_mapController.isCompleted) {
        final controller = await _mapController.future;
        controller.animateCamera(
          CameraUpdate.newLatLngZoom(LatLng(pos.latitude, pos.longitude), 16),
        );
      }
    } catch (e) {
      debugPrint('Could not get initial location: $e');
    }

    // Subscribe to position updates (guard against emulator/Play Services issues)
    if (_enableLocationStream) {
      try {
        _positionSub = Geolocator.getPositionStream(
          locationSettings: locationSettings,
        ).listen(
              (Position p) async {
            try {
              final latlng = LatLng(p.latitude, p.longitude);
              _updateUserLocation(latlng);
              if (_mapReady && _mapController.isCompleted) {
                final controller = await _mapController.future;
                controller.animateCamera(CameraUpdate.newLatLng(latlng));
              }
            } catch (inner) {
              debugPrint('Error during position update handling: $inner');
            }
          },
          onError: (err) {
            debugPrint('Position stream error: $err');
          },
          cancelOnError: true,
        );
      } catch (e, st) {
        debugPrint(
            'Failed to start position stream (likely emulator/Play Services issue): $e\n$st');
        _positionSub?.cancel();
        _positionSub = null;
      }
    } else {
      debugPrint(
          'Location streaming disabled via _enableLocationStream flag (useful for emulator).');
    }
  }

  void _updateUserLocation(LatLng pos) {
    final markerId = MarkerId('user_marker');
    final marker = Marker(
      markerId: markerId,
      position: pos,
      infoWindow: const InfoWindow(title: 'You'),
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
    );
    setState(() {
      _markers[markerId] = marker;
    });
  }

  void _togglePanel() {
    setState(() {
      _isPanelOpen = !_isPanelOpen;
      if (_isPanelOpen) {
        _panelController.forward();
      } else {
        _panelController.reverse();
      }
    });
  }

  Future<void> _handleSignOut() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginPage()),
    );
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _panelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final panelWidth = MediaQuery.of(context).size.width * 0.70;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          // Full-screen map (ensure it gets full available size)
          Positioned(
            left: 0,
            top: 0,
            right: 0,
            bottom: 0,
            child: SizedBox(
              width: MediaQuery.of(context).size.width,
              height: MediaQuery.of(context).size.height,
              child: GoogleMap(
                initialCameraPosition: _initialCamera,
                myLocationEnabled: false,
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
                markers: Set<Marker>.of(_markers.values),
                onMapCreated: (GoogleMapController controller) {
                  if (!_mapController.isCompleted) {
                    _mapController.complete(controller);
                  }
                  setState(() => _mapReady = true);
                },
              ),
            ),
          ),

          // Top left nickname and top center app title
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: _togglePanel,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.95),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withOpacity(0.08),
                              blurRadius: 6),
                        ],
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.person, size: 18, color: Colors.black54),
                          const SizedBox(width: 8),
                          Text(
                            _displayName,
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Spacer(),
                  const Text(
                    'PARA!',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.white,
                      shadows: [Shadow(color: Colors.black38, blurRadius: 3)],
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
          ),

          // Backdrop to dim map when panel is open
          if (_isPanelOpen)
            Positioned.fill(
              child: GestureDetector(
                onTap: _togglePanel,
                child: Container(color: Colors.black.withOpacity(0.35)),
              ),
            ),

          // Sliding panel (SlideTransition controlled by AnimationController)
          Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: panelWidth,
              height: MediaQuery.of(context).size.height,
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
    // Use SingleChildScrollView to avoid vertical overflow
    return SafeArea(
      child: Material(
        color: Colors.white,
        elevation: 12,
        child: SingleChildScrollView(
          child: Column(
            children: [
              // Header / Profile area
              Container(
                width: double.infinity,
                padding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: const BorderRadius.only(
                    bottomRight: Radius.circular(20),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: Colors.grey[300],
                      child: const Icon(Icons.person, color: Colors.white, size: 28),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _displayName,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Member since 2024',
                            style: TextStyle(color: Colors.black54, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Menu items
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.person_outline),
                      title: const Text('Profile'),
                      onTap: () {
                        // TODO: open profile
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.history),
                      title: const Text('History'),
                      onTap: () {
                        // TODO: history
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.settings),
                      title: const Text('Settings'),
                      onTap: () {
                        // TODO: settings
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.feedback_outlined),
                      title: const Text('User Feedback'),
                      onTap: () {
                        // TODO: feedback
                      },
                    ),
                    const Divider(),
                    ListTile(
                      leading: const Icon(Icons.logout),
                      title: const Text('Log out'),
                      onTap: () => _handleSignOut(),
                    ),
                  ],
                ),
              ),

              // Bottom branding/logo
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 18.0),
                child: Column(
                  children: [
                    Image.asset('assets/Paralogotemp.png', height: 48),
                    const SizedBox(height: 8),
                    const Text('PARA!', style: TextStyle(color: Colors.black54)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}