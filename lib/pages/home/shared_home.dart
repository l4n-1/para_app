import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:para2/pages/settings/profile_settings.dart';

/// SharedHome — unified layout for Pasahero and Tsuperhero.
/// Shows Google Map, side panel, and handles role-specific overlays.
class SharedHome extends StatefulWidget {
  final String roleLabel;
  final Future<void> Function()? onSignOut;
  final Widget? roleContent;
  final List<Widget>? roleMenu;
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
  StreamSubscription<DocumentSnapshot>? _userListener;

  bool _mapReady = false;
  bool _isPanelOpen = false;
  final bool _enableLocationStream = true;

  bool _isProfileIncomplete = false;
  bool _featuresLocked = false;

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

    _panelController = AnimationController(
      vsync: this,
      duration: _panelAnimDuration,
    );

    _panelOffset = Tween<Offset>(
      begin: const Offset(-1.0, 0.0),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _panelController, curve: Curves.easeInOut),
    );

    _listenToUserData();
    _initLocationAndMap();
  }

  /// 🔁 Live Firestore listener for profile + display name updates
  void _listenToUserData() {
    final user = _auth.currentUser;
    if (user == null) return;

    _userListener?.cancel();
    _userListener =
        _firestore.collection('users').doc(user.uid).snapshots().listen((doc) {
          // ⚙️ simplified — .exists is never null
          if (!doc.exists) return;

          final data = doc.data() ?? {};

          final missingFields = [
            if ((data['userName'] ?? '').toString().isEmpty) 'userName',
            if ((data['contact'] ?? '').toString().isEmpty) 'contact',
            if (data['dob'] == null) 'dob',
          ];

          final isIncomplete = missingFields.isNotEmpty;

          if (mounted) {
            setState(() {
              _isProfileIncomplete = isIncomplete;
              _featuresLocked = isIncomplete;

              final role = (data['role'] ?? 'pasahero').toString().toLowerCase();
              if (role == 'pasahero') {
                _displayName = (data['firstName'] ?? 'Username') as String;
              } else if (role == 'tsuperhero') {
                _displayName = (data['plateNumber'] ?? 'DRVR XXX') as String;
              } else {
                _displayName = (data['firstName'] ?? 'Username') as String;
              }
            });
          }
        });
  }

  /// 🧭 Initialize map and location with proper user feedback
  Future<void> _initLocationAndMap() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.deniedForever ||
          permission == LocationPermission.denied) {
        if (!mounted) return;
        _showLocationErrorDialog(
          title: "Location Permission Denied",
          message:
          "PARA! needs location access to show your position.\nPlease enable location access in your device settings.",
          openSettings: true,
          retryPermission: true,
        );
        return;
      }

      const locationSettings = LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 5,
      );

      Position pos;
      try {
        pos = await Geolocator.getCurrentPosition(
          locationSettings: locationSettings,
        );
      } catch (_) {
        if (!mounted) return;
        _showLocationErrorDialog(
          title: "No Location Found",
          message:
          "We couldn’t detect your location. Please check if GPS is turned on.",
          retryPermission: true,
        );
        return;
      }

      if (!mounted) return;
      _updateUserMarker(LatLng(pos.latitude, pos.longitude));

      if (_mapController.isCompleted) {
        final controller = await _mapController.future;
        if (!mounted) return;
        controller.animateCamera(
          CameraUpdate.newLatLngZoom(LatLng(pos.latitude, pos.longitude), 16),
        );
      }

      if (_enableLocationStream) {
        _positionSub = Geolocator.getPositionStream(
          locationSettings: locationSettings,
        ).listen((Position p) async {
          final latlng = LatLng(p.latitude, p.longitude);
          _updateUserMarker(latlng);
          if (_mapReady && _mapController.isCompleted) {
            final controller = await _mapController.future;
            if (!mounted) return;
            controller.animateCamera(CameraUpdate.newLatLng(latlng));
          }
        });
      }
    } catch (e) {
      if (!mounted) return;
      _showLocationErrorDialog(
        title: "Error",
        message: "An unexpected error occurred while fetching your location.",
        retryPermission: true,
      );
    }
  }

  void _showLocationErrorDialog({
    required String title,
    required String message,
    bool openSettings = false,
    bool retryPermission = false,
  }) {
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          if (openSettings)
            TextButton(
              onPressed: () async {
                await Geolocator.openAppSettings();
                if (!mounted) return;
                Navigator.pop(context);
                Future.delayed(const Duration(seconds: 2), _initLocationAndMap);
              },
              child: const Text("Open Settings"),
            ),
          TextButton(
            onPressed: () async {
              if (!mounted) return;
              Navigator.pop(context);
              if (retryPermission) {
                await Geolocator.requestPermission();
                Future.delayed(
                    const Duration(milliseconds: 500), _initLocationAndMap);
              }
            },
            child: const Text("OK"),
          ),
        ],
      ),
    );
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
    _userListener?.cancel();
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
              zoomGesturesEnabled: !_featuresLocked,
              scrollGesturesEnabled: !_featuresLocked,
              rotateGesturesEnabled: !_featuresLocked,
              markers: Set<Marker>.of(_markers.values),
              onMapCreated: (controller) {
                if (!_mapController.isCompleted) {
                  _mapController.complete(controller);
                }
                setState(() => _mapReady = true);
              },
            ),
          ),

          // ⚠️ Profile Incomplete Banner
          if (_isProfileIncomplete)
            Positioned(
              top: 80,
              left: 0,
              right: 0,
              child: Container(
                color: Colors.amber.withValues(alpha: 0.8),
                padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Expanded(
                      child: Text(
                        "⚠️ Please complete your profile to unlock all features.",
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Colors.black87,
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
                        );
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
                            color: Colors.black.withValues(alpha: 0.08),
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
                  const Text(
                    "PARA!",
                    style: TextStyle(
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
                child: Container(color: Colors.black.withValues(alpha: 0.35)),
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
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
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
              if (widget.roleMenu != null) ...widget.roleMenu!,
              ListTile(
                leading: const Icon(Icons.person),
                title: const Text('Profile Settings'),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ProfileSettingsPage(),
                    ),
                  );
                },
              ),
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
