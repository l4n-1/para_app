import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:para2/pages/settings/profile_settings.dart';

class SharedHome extends StatefulWidget {
  final String roleLabel;
  final Future<void> Function()? onSignOut;
  final Widget? roleContent;
  final List<Widget>? roleMenu;
  final Widget Function(
    BuildContext context,
    String displayName,
    LatLng? userLocation,
    void Function(LatLng picked),
  )?
  roleContentBuilder;
  final void Function(LatLng)? onMapTap;

  const SharedHome({
    super.key,
    required this.roleLabel,
    this.onSignOut,
    this.roleContent,
    this.roleMenu,
    this.roleContentBuilder,
    this.onMapTap,
  });

  static _SharedHomeState? of(BuildContext context) =>
      context.findAncestorStateOfType<_SharedHomeState>();

  @override
  State<SharedHome> createState() => _SharedHomeState();
}

class _SharedHomeState extends State<SharedHome> with TickerProviderStateMixin {
  final Completer<GoogleMapController> _mapController = Completer();
  final Map<String, Marker> _jeepMarkers = {};
  final Map<MarkerId, Marker> _markers = {};

  StreamSubscription<DatabaseEvent>? _devicesSub;
  StreamSubscription<DocumentSnapshot>? _userListener;

  bool _mapReady = false;
  bool _isPanelOpen = false;
  bool _isProfileIncomplete = false;
  bool _featuresLocked = false;

  late final AnimationController _panelController;
  late final Animation<Offset> _panelOffset;

  String _displayName = 'Username';
  LatLng? _userLocation;

  static const Duration _panelAnimDuration = Duration(milliseconds: 300);
  static const CameraPosition _initialCamera = CameraPosition(
    target: LatLng(14.5995, 120.9842),
    zoom: 14,
  );

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseDatabase _realtime = FirebaseDatabase.instance;
  BitmapDescriptor? _jeepIcon;

  final Set<Polyline> _externalPolylines = {};

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

    _loadAssets();
    _listenToUserData();

    // Only Pasahero should see jeep markers (from RTDB)
    if (widget.roleLabel.toUpperCase() != 'TSUPERHERO') {
      _subscribeDevicesRealtime();
    }
  }

  Future<void> _loadAssets() async {
    try {
      _jeepIcon = await BitmapDescriptor.fromAssetImage(
        const ImageConfiguration(size: Size(48, 48)),
        'assets/JEEP LOGO.png',
      );
    } catch (_) {
      _jeepIcon = BitmapDescriptor.defaultMarker;
    }
  }

  void _listenToUserData() {
    final user = _auth.currentUser;
    if (user == null) return;

    _userListener?.cancel();
    _userListener = _firestore
        .collection('users')
        .doc(user.uid)
        .snapshots()
        .listen((doc) {
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

              final role = (data['role'] ?? 'pasahero')
                  .toString()
                  .toLowerCase();
              if (role == 'pasahero') {
                _displayName = (data['firstName'] ?? 'Username') as String;
              } else if (role == 'tsuperhero') {
                _displayName = (data['plateNumber'] ?? 'DRVR XXX') as String;
              }
            });
          }
        });
  }

  void _subscribeDevicesRealtime() {
    _devicesSub = _realtime.ref('devices').onValue.listen((event) {
      final raw = event.snapshot.value;
      if (raw == null) return;
      final Map devices = (raw is Map) ? raw : {};

      devices.forEach((key, value) {
        final data = value as Map? ?? {};
        final lat = double.tryParse(
          data['latitude']?.toString() ?? data['lat']?.toString() ?? '',
        );
        final lng = double.tryParse(
          data['longitude']?.toString() ?? data['lng']?.toString() ?? '',
        );
        final speed = double.tryParse(
          data['speed_kmh']?.toString() ?? data['speed']?.toString() ?? '0',
        );

        if (lat == null || lng == null) return;

        _jeepMarkers[key] = Marker(
          markerId: MarkerId(key),
          position: LatLng(lat, lng),
          icon: _jeepIcon ?? BitmapDescriptor.defaultMarker,
          infoWindow: InfoWindow(
            title: key,
            snippet: 'Speed: ${(speed ?? 0).toStringAsFixed(1)} km/h',
          ),
        );
      });

      setState(() {});
    });
  }

  void addOrUpdateMarker(MarkerId id, Marker marker) {
    setState(() => _markers[id] = marker);
  }

  void removeMarker(MarkerId id) {
    setState(() => _markers.remove(id));
  }

  void updateJeepMarker(Marker marker) {
    setState(() {
      _jeepMarkers[marker.markerId.value] = marker;
    });
  }

  Set<Polyline> get externalPolylines => _externalPolylines;

  void setExternalPolylines(Set<Polyline> newPolylines) {
    setState(() {
      _externalPolylines
        ..clear()
        ..addAll(newPolylines);
    });
  }

  void clearExternalPolylines() => setState(() => _externalPolylines.clear());

  Future<GoogleMapController?> getMapController() async {
    if (!_mapController.isCompleted) return null;
    return _mapController.future;
  }

  Future<void> centerMap(LatLng pos) async {
    if (_mapController.isCompleted) {
      final controller = await _mapController.future;
      controller.animateCamera(CameraUpdate.newLatLngZoom(pos, 16));
    }
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
    _devicesSub?.cancel();
    _panelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final panelWidth = MediaQuery.of(context).size.width * 0.7;

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: GoogleMap(
              initialCameraPosition: _initialCamera,
              myLocationEnabled: false,
              zoomControlsEnabled: false,
              markers: {..._markers.values, ..._jeepMarkers.values}.toSet(),
              polylines: _externalPolylines,
              onMapCreated: (controller) {
                if (!_mapController.isCompleted) {
                  _mapController.complete(controller);
                }
                setState(() => _mapReady = true);
              },
              onTap: widget.onMapTap,
            ),
          ),
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
          if (_isPanelOpen)
            Positioned.fill(
              child: GestureDetector(
                onTap: _togglePanel,
                child: Container(color: Colors.black.withOpacity(0.35)),
              ),
            ),
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
          if (widget.roleContentBuilder != null)
            widget.roleContentBuilder!(
              context,
              _displayName,
              _userLocation,
              (LatLng picked) => setExternalPolylines({}),
            )
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 20,
                ),
                color: Colors.grey[100],
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
              if (widget.roleMenu != null) ...widget.roleMenu!,
              ListTile(
                leading: const Icon(Icons.person),
                title: const Text('Profile Settings'),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ProfileSettingsPage(),
                  ),
                ),
              ),
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
}
