import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:para2/services/RealtimeDatabaseService.dart';

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

class _SharedHomeState extends State<SharedHome> {
  final Completer<GoogleMapController> _mapController = Completer();
  final RealtimeDatabaseService _rtdbService = RealtimeDatabaseService();

  final Map<MarkerId, Marker> _markers = {};
  final Set<Polyline> _externalPolylines = {};
  StreamSubscription<DatabaseEvent>? _devicesSub;
  bool _isMapReady = false;
  LatLng? _currentUserLoc;

  // ✅ Public helper for passenger/tsuperhero to get map controller
  Future<GoogleMapController> getMapController() async => _mapController.future;

  // ✅ Marker Management
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
    setState(() => _externalPolylines.clear());
  }

  void setExternalPolylines(Set<Polyline> lines) {
    setState(() {
      _externalPolylines
        ..clear()
        ..addAll(lines);
    });
  }

  // ✅ Realtime jeep updates (for passengers)
  void _subscribeDevicesRealtime() {
    final ref = _rtdbService.database.ref('devices');
    _devicesSub = ref.onValue.listen((event) {
      if (!event.snapshot.exists || event.snapshot.value == null) return;

      final data = event.snapshot.value as Map<dynamic, dynamic>;
      final newMarkers = <MarkerId, Marker>{};

      data.forEach((id, raw) {
        if (raw is Map) {
          final lat = double.tryParse(
            raw['latitude']?.toString() ?? raw['lat']?.toString() ?? '',
          );
          final lng = double.tryParse(
            raw['longitude']?.toString() ?? raw['lng']?.toString() ?? '',
          );
          if (lat != null && lng != null) {
            final markerId = MarkerId('jeep_$id');
            final marker = Marker(
              markerId: markerId,
              position: LatLng(lat, lng),
              infoWindow: InfoWindow(title: 'Jeep $id'),
              icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueOrange,
              ),
            );
            newMarkers[markerId] = marker;
          }
        }
      });

      // ✅ Merge jeep markers without erasing user or destination markers
      setState(() {
        _markers.removeWhere(
          (key, value) => key.value.startsWith('jeep_'),
        ); // remove old jeep markers only
        _markers.addAll(newMarkers);
      });
    });
  }

  // ✅ Initialize
  @override
  void initState() {
    super.initState();
    if (widget.roleLabel.toUpperCase() != 'TSUPERHERO') {
      _subscribeDevicesRealtime();
    }
  }

  @override
  void dispose() {
    _devicesSub?.cancel();
    super.dispose();
  }

  // ✅ Center map
  Future<void> centerMap(LatLng pos) async {
    if (!_isMapReady) return;
    final ctrl = await _mapController.future;
    ctrl.animateCamera(CameraUpdate.newLatLngZoom(pos, 16));
  }

  // ✅ Build map UI
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: const BoxDecoration(color: Colors.teal),
              child: Center(
                child: Text(
                  '${widget.roleLabel} MENU',
                  style: const TextStyle(color: Colors.white, fontSize: 20),
                ),
              ),
            ),
            ...widget.roleMenu,
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Logout'),
              onTap: widget.onSignOut,
            ),
          ],
        ),
      ),
      appBar: AppBar(
        title: Text('BaryaPara ${widget.roleLabel}'),
        backgroundColor: Colors.teal,
      ),
      body: Stack(
        children: [
          GoogleMap(
            onMapCreated: (controller) {
              _mapController.complete(controller);
              setState(() => _isMapReady = true);
            },
            initialCameraPosition: const CameraPosition(
              target: LatLng(14.8528, 120.8180), // Default: Malolos
              zoom: 14,
            ),
            markers: Set<Marker>.of(_markers.values),
            polylines: _externalPolylines,
            onTap: widget.onMapTap,
            myLocationEnabled: widget.roleLabel.toUpperCase() == 'TSUPERHERO',
            myLocationButtonEnabled: true,
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              color: Colors.white70,
              padding: const EdgeInsets.all(10),
              child: widget.roleContentBuilder(
                context,
                widget.roleLabel,
                _currentUserLoc,
                widget.onMapTap ?? (_) {},
              ),
            ),
          ),
        ],
      ),
    );
  }
}
