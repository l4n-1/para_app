import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// SharedHome — A unified layout for both Pasahero and Tsuperhero.
/// Handles map, user location, top bar, and slide panel.
/// Role-specific UI (content and menu) are passed from each role screen.
class SharedHome extends StatefulWidget {
  final String roleLabel;
  final Future<void> Function()? onSignOut;
  final Widget? roleContent; // driver/passenger overlay
  final List<Widget>? roleMenu; // custom menu items
  final Widget Function(BuildContext context, String displayName)?
  roleContentBuilder;

  const SharedHome({
    super.key,
    required this.roleLabel,
    this.onSignOut,
    this.roleContent,
    this.roleMenu,
    this.roleContentBuilder,
  });

  @override
  State<SharedHome> createState() => _SharedHomeState();
}

class _SharedHomeState extends State<SharedHome> with TickerProviderStateMixin {
  final Completer<GoogleMapController> _mapController = Completer();
  final Map<MarkerId, Marker> _markers = {};
  StreamSubscription<Position>? _positionSub;

  bool _mapReady = false;
  bool _isPanelOpen = false;
  bool _enableLocationStream = true;

  late final AnimationController _panelController;
  late final Animation<Offset> _panelOffset;

  String _displayName = 'Username';

  static const Duration _panelAnimDuration = Duration(milliseconds: 300);

  static const CameraPosition _initialCamera = CameraPosition(
    target: LatLng(14.5995, 120.9842),
    zoom: 14,
  );

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();

    _loadDisplayName(); // ✅ only Firestore, never FirebaseAuth.displayName

    // 🪟 Init panel animation
    _panelController = AnimationController(
      vsync: this,
      duration: _panelAnimDuration,
    );

    _panelOffset =
        Tween<Offset>(begin: const Offset(-1.0, 0.0), end: Offset.zero).animate(
          CurvedAnimation(parent: _panelController, curve: Curves.easeInOut),
        );

    _initLocationAndMap();
  }

  Future<void> _loadDisplayName() async {
    final user = _auth.currentUser;
    if (user == null) {
      debugPrint('⚠️ No user is currently logged in.');
      return;
    }

    try {
      final docRef = _firestore.collection('users').doc(user.uid);
      final doc = await docRef.get();

      if (!doc.exists) {
        debugPrint('⚠️ Firestore doc not found for user: ${user.uid}');
        setState(() => _displayName = 'Unknown User');
        return;
      }

      final data = doc.data()!;
      debugPrint('📄 Firestore user data: $data');

      final role = (data['role'] ?? 'pasahero').toString().toLowerCase();
      String newDisplayName;

      if (role == 'pasahero') {
        newDisplayName = (data['firstName'] ?? 'Username') as String;
      } else if (role == 'tsuperhero') {
        newDisplayName = (data['plateNumber'] ?? 'DRVR XXX') as String;
      } else {
        newDisplayName = (data['firstName'] ?? 'Username') as String;
      }

      debugPrint('✅ Setting displayName to: $newDisplayName');

      setState(() {
        _displayName = newDisplayName;
      });
    } catch (e) {
      debugPrint('❌ Failed to load display name: $e');
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
        debugPrint('❌ Location permission denied.');
        return;
      }

      const locationSettings = LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 5,
      );

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: locationSettings,
      );
      _updateUserMarker(LatLng(pos.latitude, pos.longitude));

      if (_mapController.isCompleted) {
        final controller = await _mapController.future;
        controller.animateCamera(
          CameraUpdate.newLatLngZoom(LatLng(pos.latitude, pos.longitude), 16),
        );
      }

      if (_enableLocationStream) {
        _positionSub =
            Geolocator.getPositionStream(
              locationSettings: locationSettings,
            ).listen((Position p) async {
              final latlng = LatLng(p.latitude, p.longitude);
              _updateUserMarker(latlng);
              if (_mapReady && _mapController.isCompleted) {
                final controller = await _mapController.future;
                controller.animateCamera(CameraUpdate.newLatLng(latlng));
              }
            });
      }
    } catch (e) {
      debugPrint('⚠️ Error initializing location: $e');
    }
  }

  void _updateUserMarker(LatLng pos) {
    final marker = Marker(
      markerId: const MarkerId('user_marker'),
      position: pos,
      infoWindow: const InfoWindow(title: 'You'),
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
    );
    setState(() => _markers[const MarkerId('user_marker')] = marker);
  }

  void _togglePanel() {
    setState(() {
      _isPanelOpen = !_isPanelOpen;
      _isPanelOpen ? _panelController.forward() : _panelController.reverse();
    });
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _panelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final panelWidth = MediaQuery.of(context).size.width * 0.7;

    return Scaffold(
      body: Stack(
        children: [
          // 🗺️ MAP
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

          // 🔝 TOP BAR
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
                  Text(
                    "PARA!",
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.white,
                      shadows: [Shadow(color: Colors.black38, blurRadius: 3)],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 🌫️ OVERLAY
          if (_isPanelOpen)
            Positioned.fill(
              child: GestureDetector(
                onTap: _togglePanel,
                child: Container(color: Colors.black.withOpacity(0.35)),
              ),
            ),

          // 📋 SIDE PANEL
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

          // 🎯 ROLE OVERLAY
          if (widget.roleContentBuilder != null)
            widget.roleContentBuilder!(context, _displayName)
          else if (widget.roleContent != null)
            widget.roleContent!,
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
                    Flexible(
                      child: Column(
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
                    ),
                  ],
                ),
              ),

              // Custom role menu
              if (widget.roleMenu != null) ...widget.roleMenu!,

              // Logout
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('Log out'),
                onTap: widget.onSignOut,
              ),

              const Divider(),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 18.0),
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
}
