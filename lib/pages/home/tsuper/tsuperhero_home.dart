// lib/pages/tsuperhero_home.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:para2/pages/login/login.dart';

class TsuperheroHome extends StatefulWidget {
  const TsuperheroHome({super.key});

  @override
  State<TsuperheroHome> createState() => _TsuperheroHomeState();
}

class _TsuperheroHomeState extends State<TsuperheroHome>
    with TickerProviderStateMixin {
  final Completer<GoogleMapController> _mapController = Completer();
  final Map<MarkerId, Marker> _markers = {};
  StreamSubscription<Position>? _positionSub;
  bool _mapReady = false;

  bool _isPanelOpen = false;
  late final AnimationController _panelController;
  late final Animation<Offset> _panelOffset;
  static const Duration _panelAnimDuration = Duration(milliseconds: 300);

  String _plateNumber = 'DRVR-XXX';
  bool _enableLocationStream = true;

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static const CameraPosition _initialCamera = CameraPosition(
    target: LatLng(14.5995, 120.9842),
    zoom: 14,
  );

  @override
  void initState() {
    super.initState();

    _panelController = AnimationController(
      vsync: this,
      duration: _panelAnimDuration,
    );
    _panelOffset =
        Tween<Offset>(begin: const Offset(-1.0, 0.0), end: Offset.zero).animate(
          CurvedAnimation(parent: _panelController, curve: Curves.easeInOut),
        );

    _initLocationAndMap();
    _loadPlateNumber();
  }

  Future<void> _loadPlateNumber() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final doc = await _firestore.collection('users').doc(user.uid).get();
      if (doc.exists) {
        setState(() {
          _plateNumber = (doc.data()?['plateNumber'] ?? 'DRVR-XXX') as String;
        });
      }
    } catch (e) {
      debugPrint('Failed to load plate number: $e');
    }
  }

  Future<void> _initLocationAndMap() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever ||
          permission == LocationPermission.denied) {
        debugPrint('Location permission denied.');
        return;
      }
    } catch (e) {
      debugPrint('Error requesting location permission: $e');
      return;
    }

    const LocationSettings settings = LocationSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 5,
    );

    try {
      final pos = await Geolocator.getCurrentPosition();
      _updateDriverMarker(LatLng(pos.latitude, pos.longitude));
      if (_mapController.isCompleted) {
        final controller = await _mapController.future;
        controller.animateCamera(
          CameraUpdate.newLatLngZoom(LatLng(pos.latitude, pos.longitude), 16),
        );
      }
    } catch (e) {
      debugPrint('Could not get initial driver location: $e');
    }

    if (_enableLocationStream) {
      _positionSub = Geolocator.getPositionStream(locationSettings: settings)
          .listen((pos) async {
            final latlng = LatLng(pos.latitude, pos.longitude);
            _updateDriverMarker(latlng);
            if (_mapReady && _mapController.isCompleted) {
              final controller = await _mapController.future;
              controller.animateCamera(CameraUpdate.newLatLng(latlng));
            }
          });
    }
  }

  void _updateDriverMarker(LatLng pos) {
    final markerId = MarkerId('driver_marker');
    final marker = Marker(
      markerId: markerId,
      position: pos,
      infoWindow: const InfoWindow(title: 'Your Jeepney'),
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
    );
    setState(() => _markers[markerId] = marker);
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
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => const LoginPage()));
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
      body: Stack(
        children: [
          Positioned.fill(
            child: GoogleMap(
              initialCameraPosition: _initialCamera,
              myLocationEnabled: false,
              zoomControlsEnabled: false,
              markers: Set<Marker>.of(_markers.values),
              onMapCreated: (controller) {
                if (!_mapController.isCompleted) {
                  _mapController.complete(controller);
                }
                setState(() => _mapReady = true);
              },
            ),
          ),

          // Top Bar
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
                            color: Colors.black.withOpacity(0.08),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.directions_bus,
                            size: 18,
                            color: Colors.black54,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _plateNumber,
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
                    'TSUPERHERO',
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

          // Map dim overlay
          if (_isPanelOpen)
            Positioned.fill(
              child: GestureDetector(
                onTap: _togglePanel,
                child: Container(color: Colors.black.withOpacity(0.35)),
              ),
            ),

          // Sliding side panel
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

          // Driver Control Button (temporary placeholder)
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 40.0),
              child: ElevatedButton.icon(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Go Online tapped!')),
                  );
                },
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 40,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
                icon: const Icon(Icons.power_settings_new),
                label: const Text(
                  'Go Online',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidePanel(BuildContext context) {
    return SafeArea(
      child: Material(
        color: Colors.white,
        elevation: 12,
        child: SingleChildScrollView(
          child: Column(
            children: [
              // Header
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 20,
                ),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: const BorderRadius.only(
                    bottomRight: Radius.circular(20),
                  ),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: Colors.grey[300],
                      child: const Icon(
                        Icons.directions_bus,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _plateNumber,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Active Driver',
                            style: TextStyle(
                              color: Colors.black54,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Menu items
              ListTile(
                leading: const Icon(Icons.qr_code_scanner),
                title: const Text('Scan Activation QR'),
                onTap: () {
                  // TODO: implement QR activation
                },
              ),
              ListTile(
                leading: const Icon(Icons.route),
                title: const Text('Assigned Route'),
                onTap: () {},
              ),
              ListTile(
                leading: const Icon(Icons.settings),
                title: const Text('Settings'),
                onTap: () {},
              ),
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('Log out'),
                onTap: _handleSignOut,
              ),

              const Divider(),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 18.0),
                child: Column(
                  children: [
                    Image.asset('assets/Paralogotemp.png', height: 48),
                    const SizedBox(height: 8),
                    const Text(
                      'PARA! - TsuperHero',
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
}
