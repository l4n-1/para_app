import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:para2/pages/login/login.dart';
import 'package:para2/pages/home/shared_home.dart';
import 'package:para2/pages/login/qr_scan_page.dart';
import 'package:para2/services/RealtimeDatabaseService.dart';
import 'dart:math' as math;
import 'package:para2/services/ui_utils.dart';
import 'package:para2/services/button_actions.dart';
import 'package:para2/services/map_theme_service.dart';
import 'package:para2/services/follow_service.dart';
import 'package:para2/services/route_utils.dart';
import 'package:para2/theme/app_icons.dart';
import 'package:para2/pages/settings/profile_settings.dart';
import 'package:para2/pages/biyahe/biyahe_logs_page.dart';
import 'package:para2/services/snackbar_service.dart';
import 'package:para2/widgets/destination_display.dart';



class TsuperheroHome extends StatefulWidget {
  const TsuperheroHome({super.key});

  @override
  State<TsuperheroHome> createState() => _TsuperheroHomeState();
}

class _TsuperheroHomeState extends State<TsuperheroHome> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final RealtimeDatabaseService _rtdbService = RealtimeDatabaseService();

  StreamSubscription? _trackerSub;
  StreamSubscription<QuerySnapshot>? _paraSub;
  Marker? _jeepMarker;
  bool _hasCentered = false;
  // Track which passenger markers we've added so we can remove them when out of range
  final Set<String> _visiblePassengerIds = {};

  // Driver route points and polylines
  List<LatLng>? _routePoints;
  final Set<Polyline> _routePolylines = {};
  late final PolylinePoints _polylinePoints;
  // Google API key (reused from pasahero_home.dart)
  static const String _googleApiKey = 'AIzaSyCb4q7iicIT4TD8qjPQxHtlxYn4tEj4WOY';
  // Index of the next route point the jeep should head to (used for active segment)
  int _nextRoutePointIndex = 0;
  // How many downstream route vertices to include in the active segment
  // beyond the immediate next point. Increase to show more of the upcoming
  // route in the green active polyline.
  int _activeSegmentLookahead = 3;
  // Connector cache: a road-following sub-route from the jeep position to
  // a point on the route. We request this from Directions sparingly and
  // cache the result to avoid repeated API calls on frequent GPS updates.
  List<LatLng>? _activeConnector;
  LatLng? _lastConnectorOrigin;
  LatLng? _lastConnectorTarget;
  DateTime? _lastConnectorTime;
  // Minimum time between connector requests (ms)
  int _connectorCooldownMs = 8000;
  // Minimum movement (meters) required to force a new connector request
  double _connectorMoveThreshold = 20.0;

  String _plateNumber = 'DRVR-XXX';
  bool _isOnline = false;
  String? _trackerId;
  String _displayName = 'Driver';

  // Manual passenger counter
  int _currentPassengers = 0;
  int _maxCapacity = 20;
  bool _isEditingCapacity = false;
  // Driver actions state
  bool _showRouteMenu = false;
  String _selectedRoute = '';
  // The route the driver has confirmed/published (saved to users/{uid}/currentRoute)
  String? _currentRouteSaved;
  // Will be populated from Firestore `jeepney_routes` collection at runtime
  final List<String> _presetRoutes = [];
  // The BuildContext provided by SharedHome's roleContentBuilder (descendant)
  BuildContext? _sharedHomeContext;
  // A GlobalKey attached to the SharedHome so the parent can access its state
  final GlobalKey _sharedHomeKey = GlobalKey();

  // Helper to resolve the SharedHome state. Prefer the captured descendant
  // context (when the roleContentBuilder has been built); fall back to the
  // GlobalKey's currentState so calls made before the child builds still
  // reach the SharedHome instance once it's available.
  dynamic _getSharedHomeState() {
    try {
      if (_sharedHomeContext != null) return SharedHome.of(_sharedHomeContext!);
    } catch (_) {}
    try {
      return _sharedHomeKey.currentState as dynamic?;
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _polylinePoints = PolylinePoints();
    _initDriverData();
    _loadUserDisplayName();
    // Populate available routes from Firestore so the driver can choose any route
    _loadAllRoutes();
    _subscribePassengerRequests();
  }

  Future<void> _initDriverData() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final doc = await _firestore.collection('users').doc(user.uid).get();
      if (!doc.exists) return;

      final data = doc.data() ?? {};
      _plateNumber = data['plateNumber'] ?? 'DRVR-XXX';
      final boxId = data['boxClaimed'];

      if (boxId != null) {
        final boxDoc = await _firestore
            .collection('baryaBoxes')
            .doc(boxId)
            .get();
        if (boxDoc.exists) {
          _trackerId = boxDoc.data()?['trackerId'];
        }
      }

      // If the user document contains a saved/assigned route name, load it
      // automatically so the driver sees their official route immediately.
      final savedRoute = (data['currentRoute'] as String?) ?? (data['selectedRoute'] as String?) ?? (data['route'] as String?) ?? (data['assignedRoute'] as String?);
      if (savedRoute != null && savedRoute.isNotEmpty) {
        _selectedRoute = savedRoute;
        // Fire-and-forget: display route polyline (no need to block init)
        _loadRoutePointsForName(savedRoute);
      }

      // Load current passenger count from RTDB
      if (_trackerId != null) {
        await _loadCurrentPassengerCount();
        _listenToTracker(_trackerId!);
      }

      setState(() {});
    } catch (e) {
      debugPrint('Error initializing driver data: $e');
    }
  }

  Future<void> _loadCurrentPassengerCount() async {
    if (_trackerId == null) return;

    try {
      final trackerRef = _rtdbService.getJeepneyGpsRef(_trackerId!);
      final snapshot = await trackerRef.get();
      if (snapshot.exists) {
        final data = snapshot.value as Map<dynamic, dynamic>?;
        if (data != null) {
          setState(() {
            _currentPassengers = (data['currentPassengers'] as int?) ?? 0;
            _maxCapacity = (data['maxCapacity'] as int?) ?? 20;
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading passenger count: $e');
    }
  }

  void _listenToTracker(String trackerId) {
    _trackerSub?.cancel();

    final trackerRef = _rtdbService.getJeepneyGpsRef(trackerId);
    debugPrint("📡 Listening to tracker path: devices/$trackerId");

    _trackerSub = trackerRef.onValue.listen((event) async {
      final snapshot = event.snapshot;
      if (!snapshot.exists || snapshot.value == null) return;

      final raw = snapshot.value;
      if (raw is! Map) return;

      final data = raw.cast<String, dynamic>();
      final lat = double.tryParse(
        data['latitude']?.toString() ?? data['lat']?.toString() ?? '',
      );
      final lng = double.tryParse(
        data['longitude']?.toString() ?? data['lng']?.toString() ?? '',
      );
      final speed = double.tryParse(
        data['speed_kmh']?.toString() ?? data['speed']?.toString() ?? '0',
      );

      if (lat == null || lng == null) {
        debugPrint("⚠️ Invalid lat/lng for tracker $trackerId: $data");
        return;
      }

      final pos = LatLng(lat, lng);

      // Use medium icon by default (will be updated by SharedHome's zoom logic)
      final marker = Marker(
        markerId: const MarkerId('tsuperhero_jeep'),
        position: pos,
        icon: _isOnline
            ? (AppIcons.jeepIconMedium ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen))
            : BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
        infoWindow: InfoWindow(
          title: _isOnline ? '$_plateNumber (Online)' : '$_plateNumber (Offline)',
          snippet: 'Speed: ${(speed ?? 0).toStringAsFixed(1)} km/h | Passengers: $_currentPassengers/$_maxCapacity',
        ),
        rotation: double.tryParse(data['course']?.toString() ?? '0') ?? 0,
        anchor: const Offset(0.5, 0.5),
        flat: true,
      );

      setState(() => _jeepMarker = marker);

      final sharedHome = _getSharedHomeState();
      if (sharedHome != null) {
        sharedHome.addOrUpdateMarker(const MarkerId('tsuperhero_jeep'), marker);
        // Remove the phone user marker for drivers so the map focuses on the box
        sharedHome.removeMarker(const MarkerId('user_marker'));
        // Also remove the duplicate device marker (created by SharedHome's
        // RTDB devices subscription) so we don't show two jeep markers for
        // the same tracker. The device marker uses id `jeep_<trackerId>`.
        try {
          sharedHome.removeJeepMarker(trackerId);
        } catch (e) {
          debugPrint('Could not remove duplicate jeep marker: $e');
        }

        // If follow mode is enabled, center on the jeep (tracker) instead of phone
        if (FollowService.instance.isFollowing.value) {
          try {
            await sharedHome.centerMap(pos);
          } catch (e) {
            debugPrint('Error centering on tracker while following: $e');
          }
        } else if (!_hasCentered) {
          // Initial center when tracker first appears
              await sharedHome.centerMap(pos);
          _hasCentered = true;
        }
        // Update active route segment based on current jeep position
            try {
              await _updateActiveSegment(pos);
            } catch (e) {
              debugPrint('Error updating active route segment: $e');
            }
      }

      debugPrint("📍 Jeep updated: ($lat, $lng) - Online: $_isOnline - Passengers: $_currentPassengers/$_maxCapacity");
    });
  }

  // Haversine distance in meters
  double _distanceMeters(LatLng a, LatLng b) {
    const R = 6371000.0; // meters
    final lat1 = a.latitude * (math.pi / 180.0);
    final lat2 = b.latitude * (math.pi / 180.0);
    final dLat = (b.latitude - a.latitude) * (math.pi / 180.0);
    final dLon = (b.longitude - a.longitude) * (math.pi / 180.0);
    final sinDlat = math.sin(dLat / 2);
    final sinDlon = math.sin(dLon / 2);
    final h = sinDlat * sinDlat + math.cos(lat1) * math.cos(lat2) * sinDlon * sinDlon;
    final c = 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
    return R * c;
  }

  // Compute the closest point on segment AB to point P (returns LatLng).
  // Works in latitude/longitude space; accurate enough for short distances.
  LatLng _closestPointOnSegment(LatLng a, LatLng b, LatLng p) {
    final double ax = a.latitude;
    final double ay = a.longitude;
    final double bx = b.latitude;
    final double by = b.longitude;
    final double px = p.latitude;
    final double py = p.longitude;

    final double vx = bx - ax;
    final double vy = by - ay;
    final double wx = px - ax;
    final double wy = py - ay;

    final double denom = vx * vx + vy * vy;
    if (denom == 0) return a;

    double t = (vx * wx + vy * wy) / denom;
    if (t < 0) t = 0;
    if (t > 1) t = 1;

    return LatLng(ax + vx * t, ay + vy * t);
  }

  // Build (or reuse) a road-following connector from origin -> target
  // using the Directions API. This function caches the last connector and
  // respects a cooldown to avoid excessive API calls on frequent updates.
  Future<List<LatLng>?> _buildConnectorIfNeeded(LatLng origin, LatLng target) async {
    try {
      final now = DateTime.now();
      // Reuse cached connector if origin/target are close to previous ones
      if (_activeConnector != null && _lastConnectorOrigin != null && _lastConnectorTarget != null && _lastConnectorTime != null) {
        final dOrigin = _distanceMeters(origin, _lastConnectorOrigin!);
        final dTarget = _distanceMeters(target, _lastConnectorTarget!);
        final dt = now.difference(_lastConnectorTime!).inMilliseconds;
        if (dOrigin <= _connectorMoveThreshold && dTarget <= 10.0 && dt <= _connectorCooldownMs) {
          return _activeConnector;
        }
      }

      // Too many Directions calls can be expensive; guard by cooldown.
      if (_lastConnectorTime != null) {
        final dt = now.difference(_lastConnectorTime!).inMilliseconds;
        if (dt < _connectorCooldownMs) {
          // If we've recently asked and nothing changed much, reuse cached
          // connector even if origin moved slightly.
          if (_activeConnector != null) return _activeConnector;
        }
      }

      // Issue a single Directions call from origin -> target and decode
      final result = await _polylinePoints.getRouteBetweenCoordinates(
        googleApiKey: _googleApiKey,
        request: PolylineRequest(
          origin: PointLatLng(origin.latitude, origin.longitude),
          destination: PointLatLng(target.latitude, target.longitude),
          mode: TravelMode.driving,
          avoidHighways: false,
          avoidTolls: false,
        ),
      );

      if (result.points.isEmpty) {
        debugPrint('Tsuper: connector directions returned no points');
        return null;
      }

      final conn = result.points.map((p) => LatLng(p.latitude, p.longitude)).toList();
      _activeConnector = conn;
      _lastConnectorOrigin = origin;
      _lastConnectorTarget = target;
      _lastConnectorTime = now;
      debugPrint('Tsuper: built connector with ${conn.length} points');
      return conn;
    } catch (e) {
      debugPrint('Tsuper: error building connector: $e');
      return null;
    }
  }

  /// Build a road-following route by requesting Directions between each
  /// Build a road-following route by requesting Directions for larger
  /// segments (chunked) to reduce detours and API calls. This attempts to
  /// follow roads between the provided vertices while avoiding issuing a
  /// Directions call for every adjacent pair (which can produce detours on
  /// sparse vertex lists). Falls back to raw vertices if any lookup fails.
  Future<List<LatLng>> _buildDriverRouteFromPoints(List<LatLng> pts) async {
    if (pts.length < 2) return pts;
    final List<LatLng> assembled = [];
    // Choose chunk size to limit waypoint complexity and API calls. 6-10 is a
    // reasonable tradeoff for mid-length routes; adjust if needed.
    const int chunkSize = 8;
    try {
      for (int start = 0; start < pts.length - 1; start += chunkSize) {
        final end = (start + chunkSize < pts.length - 1) ? start + chunkSize : pts.length - 1;
        final a = pts[start];
        final b = pts[end];

        // Request a driving route between a and b. If the result is empty,
        // fallback to inserting raw intermediate vertices from start..end.
        final result = await _polylinePoints.getRouteBetweenCoordinates(
          googleApiKey: _googleApiKey,
          request: PolylineRequest(
            origin: PointLatLng(a.latitude, a.longitude),
            destination: PointLatLng(b.latitude, b.longitude),
            mode: TravelMode.driving,
            avoidHighways: false,
            avoidTolls: false,
          ),
        );

        if (result.points.isNotEmpty) {
          for (final p in result.points) {
            final latlng = LatLng(p.latitude, p.longitude);
            if (assembled.isEmpty || assembled.last.latitude != latlng.latitude || assembled.last.longitude != latlng.longitude) {
              assembled.add(latlng);
            }
          }
        } else {
          // Insert raw vertices for this chunk if Directions returned nothing
          for (int k = start; k <= end; k++) {
            final v = pts[k];
            if (assembled.isEmpty || assembled.last.latitude != v.latitude || assembled.last.longitude != v.longitude) {
              assembled.add(v);
            }
          }
        }
      }
      return assembled;
    } catch (e) {
      debugPrint('Tsuper: failed to build driver route via Directions API: $e');
      return pts;
    }
  }

  /// Update the small active polyline segment from the jeep's current
  /// position to the next route point ahead. Only this segment is updated
  /// frequently; the full route stays in `_routePolylines` as `driverRoute`.
  Future<void> _updateActiveSegment(LatLng jeepPos) async {
    if (_routePoints == null || _routePoints!.isEmpty) return;

    // Find nearest route index
    int nearestIdx = 0;
    double best = double.infinity;
    for (int i = 0; i < _routePoints!.length; i++) {
      final d = _distanceMeters(jeepPos, _routePoints![i]);
      if (d < best) {
        best = d;
        nearestIdx = i;
      }
    }

    // Candidate next point is the next index after the nearest
    int candidateNext = nearestIdx + 1;

    // If we're at or beyond the last point, remove any active segment
    if (candidateNext >= _routePoints!.length) {
      _routePolylines.removeWhere((p) => p.polylineId.value == 'active_segment');
      debugPrint('Tsuper: reached end of route, removed active segment');
      _nextRoutePointIndex = _routePoints!.length - 1;
    } else {
      final nextPt = _routePoints![candidateNext];

      // If we're very close to the next point, treat it as reached: remove highlight
      const double reachThreshold = 10.0; // meters
      final distToNext = _distanceMeters(jeepPos, nextPt);
      if (distToNext <= reachThreshold) {
        // Advance next index so next active segment picks the following point
        _nextRoutePointIndex = candidateNext;
        _routePolylines.removeWhere((p) => p.polylineId.value == 'active_segment');
        debugPrint('Tsuper: reached route point $candidateNext (dist=${distToNext.toStringAsFixed(1)}m) — clearing active highlight');
      } else {
        // Build an active segment that follows the road: project the jeep
        // position onto the nearest route segment and use the route geometry
        // between that projection and the next route point.
        LatLng proj = jeepPos;
        int projSegIndex = nearestIdx;
        try {
          // Find the nearest route segment (not just nearest vertex) and project
          // the jeep position onto that segment so the active line follows
          // the actual route geometry.
          double bestSegDist = double.infinity;
          for (int s = 0; s < _routePoints!.length - 1; s++) {
            final a = _routePoints![s];
            final b = _routePoints![s + 1];
            final cand = _closestPointOnSegment(a, b, jeepPos);
            final d = _distanceMeters(jeepPos, cand);
            if (d < bestSegDist) {
              bestSegDist = d;
              proj = cand;
              projSegIndex = s;
            }
          }
        } catch (e) {
          debugPrint('Tsuper: projection over segments failed, using raw jeepPos: $e');
          proj = jeepPos;
          projSegIndex = nearestIdx;
        }

        // Collect route geometry from the jeep marker position to the next
        // route point so the active segment visually connects to the marker.
        final List<LatLng> seg = [];
        // Try to build/ reuse a road-following connector from jeep -> proj
        // so the line follows streets instead of drawing a straight line.
        List<LatLng>? connector;
        try {
          connector = await _buildConnectorIfNeeded(jeepPos, proj);
        } catch (e) {
          debugPrint('Tsuper: connector build failed: $e');
          connector = null;
        }

        if (connector != null && connector.isNotEmpty) {
          // Start the segment with the connector (already begins at jeepPos)
          seg.addAll(connector);
          // Ensure the connector ends at or near the projection; if not, append proj
          final last = seg.last;
          if (_distanceMeters(last, proj) > 3.0) seg.add(proj);
        } else {
          // Fallback: start directly from jeepPos and include projection
          seg.add(jeepPos);
          final double projDist = _distanceMeters(jeepPos, proj);
          if (projDist > 1.0) seg.add(proj);
        }

        final from = projSegIndex + 1;
        final to = math.min(candidateNext + _activeSegmentLookahead, _routePoints!.length - 1);
        if (from <= to) {
          seg.addAll(_routePoints!.sublist(from, to + 1));
        } else {
          seg.add(nextPt);
        }

        final active = Polyline(
          polylineId: const PolylineId('active_segment'),
          points: seg,
          color: const Color.fromARGB(144, 41, 182, 192),
          width: 6,
        );

        // Replace any existing active segment
        _routePolylines.removeWhere((p) => p.polylineId.value == 'active_segment');
        _routePolylines.add(active);
        _nextRoutePointIndex = candidateNext;
        debugPrint('Tsuper: active segment (road-following) to point $candidateNext (dist=${distToNext.toStringAsFixed(1)}m)');
        // Publish the active segment to Firestore for pasahero clients to read.
        try {
          if (_isOnline) {
            final user = _auth.currentUser;
            if (user != null) {
              final routeName = (_currentRouteSaved != null && _currentRouteSaved!.isNotEmpty) ? _currentRouteSaved! : _selectedRoute;
              if (routeName.isNotEmpty) {
                final routeDoc = _routeDocIdFromName(routeName);
                final docRef = _firestore.collection('active_routes').doc(routeDoc).collection('drivers').doc(user.uid);
                final segPayload = seg.map((p) => {'lat': p.latitude, 'lng': p.longitude}).toList();
                await docRef.set({'active_segment': segPayload, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
              }
            }
          }
        } catch (e) {
          debugPrint('Tsuper: failed to publish active_segment to Firestore: $e');
        }
      }
    }

    // Ensure the full driver route polyline remains in the set (id: driverRoute)
    final hasDriverRoute = _routePolylines.any((p) => p.polylineId.value == 'driverRoute');
    if (!hasDriverRoute && _routePoints != null && _routePoints!.isNotEmpty) {
      _routePolylines.add(Polyline(polylineId: const PolylineId('driverRoute'), points: _routePoints!, color: Colors.orangeAccent, width: 5));
    }

    // Push updated external polylines to SharedHome so they render on the map
    // Only push when the driver is online; when offline we must not display
    // live/active segments to other users.
    final shared = _getSharedHomeState();
    try {
      if (_isOnline) {
        shared?.setExternalPolylines(_routePolylines);
        debugPrint('Tsuper: updated active segment (nextIdx=$_nextRoutePointIndex)');
      } else {
        debugPrint('Tsuper: offline - suppressed pushing external polylines');
      }
    } catch (e) {
      debugPrint('Error pushing external polylines to SharedHome: $e');
    }
  }

  // Manual passenger counter methods
  void _incrementPassengers() {
    if (_currentPassengers < _maxCapacity) {
      setState(() {
        _currentPassengers++;
      });
      _updatePassengerCountInRTDB();
    }
  }

  void _decrementPassengers() {
    if (_currentPassengers > 0) {
      setState(() {
        _currentPassengers--;
      });
      _updatePassengerCountInRTDB();
    }
  }

  Future<void> _updatePassengerCountInRTDB() async {
    if (_trackerId == null) return;

    try {
      final trackerRef = _rtdbService.getJeepneyGpsRef(_trackerId!);
      await trackerRef.update({
        'currentPassengers': _currentPassengers,
        'maxCapacity': _maxCapacity,
        'hasAvailableSeats': _currentPassengers < _maxCapacity,
        'lastUpdate': ServerValue.timestamp,
      });
      debugPrint("✅ Updated passenger count: $_currentPassengers/$_maxCapacity");
    } catch (e) {
      debugPrint('❌ Error updating passenger count: $e');
    }
  }

  void _showCapacityEditor() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Set Maximum Capacity'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Current: $_maxCapacity passengers'),
            const SizedBox(height: 16),
            Slider(
              value: _maxCapacity.toDouble(),
              min: 10,
              max: 30,
              divisions: 20,
              label: _maxCapacity.toString(),
              onChanged: (value) {
                setState(() {
                  _maxCapacity = value.toInt();
                });
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              _updatePassengerCountInRTDB();
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Widget _buildEarningsSection() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green[100]!),
      ),
      child: Column(
        children: [
          const Row(
            children: [
              Icon(Icons.attach_money, color: Colors.green),
              SizedBox(width: 8),
              Text(
                'Today\'s Earnings',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Digital Rides:'),
              Text('₱0.00', style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Cash Rides:'),
              Text('₱0.00', style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          const Divider(),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total Earnings:'),
              Text('₱0.00',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: Colors.green
                  )),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '💡 Digital payments earn you 90% of the fare',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
              fontStyle: FontStyle.italic,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Future<void> _toggleOnlineStatus() async {
    setState(() => _isOnline = !_isOnline);
    try {
      final user = _auth.currentUser;
      if (user != null) {
        await _firestore.collection('users').doc(user.uid).update({
          'isOnline': _isOnline,
          'lastStatusChange': FieldValue.serverTimestamp(),
        });

        if (_trackerId != null) {
          final trackerRef = _rtdbService.getJeepneyGpsRef(_trackerId!);
          await trackerRef.update({
            'isOnline': _isOnline,
            'currentPassengers': _currentPassengers,
            'maxCapacity': _maxCapacity,
            'hasAvailableSeats': _currentPassengers < _maxCapacity,
            'lastUpdate': ServerValue.timestamp,
          });
        }
      }
      final sharedHome = _getSharedHomeState();

      if (_isOnline) {
        // SharedHome will open the bottom panel when it receives the
        // updated `isDriverOnline` flag from this widget. Do not toggle
        // the panel directly here to avoid races and double-toggles.
        // Ensure the SharedHome displays this driver's polylines while online.
        try {
          sharedHome?.clearExternalPolylines();
          if (_routePolylines.isNotEmpty) sharedHome?.setExternalPolylines(_routePolylines);
        } catch (_) {}
        // If a route is already selected and confirmed, publish it so pasaheros can see it
        if (_currentRouteSaved != null && _currentRouteSaved!.isNotEmpty) {
          await _publishActiveRoute(_currentRouteSaved!);
        }
        SnackbarService.show(context, '🟢 You are now ONLINE - Visible to passengers', duration: const Duration(seconds: 2));
      } else {
        // Going offline: remove any online-only map data (published route)
        if (user != null) {
          await _removeActiveRouteForUser(user.uid);
        }
        // Going offline: clear any external polylines so other users won't
        // see live/active segments for this driver. Do NOT re-add route
        // polylines — per design polylines are only visible while online.
        try {
          sharedHome?.clearExternalPolylines();
        } catch (_) {}
        SnackbarService.show(context, '🔴 You are now OFFLINE', duration: const Duration(seconds: 2));
      }
    } catch (e) {
      debugPrint('Error updating online status: $e');
    }
  }

  @override
  void dispose() {
    _trackerSub?.cancel();
    _paraSub?.cancel();
    super.dispose();
  }

  void _subscribePassengerRequests() {
    _paraSub?.cancel();
    _paraSub = FirebaseFirestore.instance
        .collection('para_requests')
        .where('status', whereIn: ['pending', 'active'])
        .snapshots()
        .listen((snapshot) {
      final sharedHome = _getSharedHomeState();
      if (sharedHome == null) return;

      final currentlyVisible = <String>{};

      for (final doc in snapshot.docs) {
        final raw = doc.data();
        final data = Map<String, dynamic>.from(raw as Map);
        if (data['passengerLocation'] == null) continue;
        final gp = data['passengerLocation'] as GeoPoint;
        final pLoc = LatLng(gp.latitude, gp.longitude);

        bool shouldShow = false;

        // If we have the jeep tracker position, show passengers within a radius
        if (_jeepMarker != null) {
          final distKm = _distanceKm(pLoc, _jeepMarker!.position);
          if (distKm <= 3.0) {
            shouldShow = true;
          }
        }

        // If the passenger document contains route points and the driver has a route,
        // check for route overlap. (This requires both sides to provide route arrays.)
        // (Optional) If the passenger document contains route points and the driver
        // has a route, you could check for route overlap using `findLastOverlappingNode`.
        // That logic is left as a hook for when driver route polylines/points are available.

        final pid = doc.id;
        // If driver has route points, attempt route overlap check with passenger route
        if (!shouldShow && _routePoints != null && data['routePoints'] != null) {
            try {
              final List<dynamic> rp = data['routePoints'];
              final passengerRoute = rp.map((e) {
                if (e is GeoPoint) return LatLng(e.latitude, e.longitude);
                if (e is Map && e['lat'] != null && e['lng'] != null) return LatLng((e['lat'] as num).toDouble(), (e['lng'] as num).toDouble());
                return null;
              }).whereType<LatLng>().toList();

              final overlap = findLastOverlappingNode(_routePoints!, passengerRoute, toleranceMeters: 25.0);
              if (overlap != null) {
                shouldShow = true;
              }
            } catch (_) {}
        }

        if (shouldShow) {
          currentlyVisible.add(pid);
          final marker = Marker(
            markerId: MarkerId('pasahero_$pid'),
            position: pLoc,
            infoWindow: InfoWindow(title: data['passengerName'] ?? 'Passenger'),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          );
          sharedHome.addOrUpdateMarker(MarkerId('pasahero_$pid'), marker);
        }
      }

      // Remove any previously visible passenger markers that are no longer in range
      final toRemove = _visiblePassengerIds.difference(currentlyVisible);
      for (final pid in toRemove) {
        sharedHome.removeMarker(MarkerId('pasahero_$pid'));
      }

      _visiblePassengerIds
        ..clear()
        ..addAll(currentlyVisible);
    }, onError: (e) {
      debugPrint('para_requests subscription error: $e');
    });
  }

  /// Load route points for a named route from Firestore collection `jeepney_routes`.
  /// The `name` should match the document `displayName` field or the document id.
  Future<void> _loadRoutePointsForName(String name) async {
    try {
      // Try to find by displayName first
      final q = await _firestore.collection('jeepney_routes').where('displayName', isEqualTo: name).limit(1).get();
      DocumentSnapshot? doc;
      if (q.docs.isNotEmpty) {
        doc = q.docs.first;
      } else {
        // Fallback: try document id
        final alt = await _firestore.collection('jeepney_routes').doc(name).get();
        if (alt.exists) doc = alt;
      }

      if (doc == null || !doc.exists) {
        debugPrint('Route not found for name: $name');
        return;
      }

      final data = doc.data() as Map<String, dynamic>?;
      if (data == null) return;

      final rawPoints = data['points'];
      if (rawPoints == null || rawPoints is! List) return;

      final pts = <LatLng>[];
      for (final p in rawPoints) {
        if (p == null) continue;
        if (p is GeoPoint) {
          pts.add(LatLng(p.latitude, p.longitude));
        } else if (p is Map) {
          final lat = (p['lat'] as num?)?.toDouble();
          final lng = (p['lng'] as num?)?.toDouble();
          if (lat != null && lng != null) pts.add(LatLng(lat, lng));
        }
      }

      if (pts.isEmpty) {
        debugPrint('No route points found for route: $name');
        return;
      }

      // Attempt to build a road-following route (using Directions API in
      // chunked segments). If the builder fails we fall back to raw
      // Firestore vertices so the driver still sees a valid route.
      List<LatLng> finalRoutePoints = pts;
      try {
        final built = await _buildDriverRouteFromPoints(pts);
        if (built.isNotEmpty) {
          finalRoutePoints = built;
        }
        debugPrint('Tsuper: built driver route (${finalRoutePoints.length} pts) from original ${pts.length} vertices');
      } catch (e) {
        debugPrint('Tsuper: directions-based build failed, using raw points: $e');
        finalRoutePoints = pts;
      }

      setState(() {
        _routePoints = finalRoutePoints;
        _routePolylines
          ..clear()
          ..add(Polyline(
            polylineId: const PolylineId('driverRoute'),
            color: const Color.fromARGB(255, 90, 10, 165),
            width: 5,
            points: finalRoutePoints,
          ));
      });

      // Push to SharedHome (clear previous external polylines first)
      final shared = _getSharedHomeState();
      shared?.clearExternalPolylines();
      // Only expose external polylines when the driver is online.
      if (_isOnline) {
        shared?.setExternalPolylines(_routePolylines);
      }
      debugPrint('Loaded route points for $name (${pts.length} points)');
    } catch (e) {
      debugPrint('Error loading route points for $name: $e');
    }
  }

  /// Load all routes available in Firestore `jeepney_routes` collection and
  /// populate `_presetRoutes` with `displayName` (fallback to doc id).
  Future<void> _loadAllRoutes() async {
    try {
      final q = await _firestore.collection('jeepney_routes').get();
      final routes = <String>[];
      for (final doc in q.docs) {
        final data = doc.data() as Map<String, dynamic>?;
        final display = (data != null && data['displayName'] is String) ? (data['displayName'] as String).trim() : null;
        if (display != null && display.isNotEmpty) {
          routes.add(display);
        } else {
          routes.add(doc.id);
        }
      }
      setState(() {
        _presetRoutes
          ..clear()
          ..addAll(routes);
      });
      debugPrint('Loaded ${routes.length} routes from jeepney_routes');
    } catch (e) {
      debugPrint('Error loading all routes: $e');
    }
  }

  /// Publish the driver's active route to Firestore so other users (pasahero)
  /// can see it. Stored in `active_routes/{driverUid}` with a `routeName` and
  /// `points` array of {lat,lng} maps.
  Future<void> _publishActiveRoute(String routeName) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      // Ensure we have route points loaded locally; if not, load them first
      if (_routePoints == null || _routePoints!.isEmpty) {
        await _loadRoutePointsForName(routeName);
      }

      if (_routePoints == null || _routePoints!.isEmpty) {
        debugPrint('No route points to publish for $routeName');
        return;
      }

      final pointsPayload = _routePoints!.map((p) => {'lat': p.latitude, 'lng': p.longitude}).toList();

      // If a different route was previously published by this driver, remove
      // that previous publication before publishing the new one so we don't
      // leave stale docs under the old active_routes/{route}/drivers/{uid}.
      try {
        final previous = (_currentRouteSaved != null && _currentRouteSaved!.isNotEmpty) ? _currentRouteSaved! : null;
        if (previous != null && previous != routeName) {
          await _removeActiveRouteForUser(user.uid, routeName: previous);
        }
      } catch (e) {
        debugPrint('Tsuper: failed to remove previous active route: $e');
      }

      // Save currentRoute to users doc (always save so driver preferences persist)
      await _firestore.collection('users').doc(user.uid).update({'currentRoute': routeName});
      // Only publish an active route for others to see if the driver is online.
      // New structure: active_routes/{routeDoc}/drivers/{uid} => { driverId, routeName, points, updatedAt }
        if (_isOnline) {
          final routeDoc = _routeDocIdFromName(routeName);
          final docRef = _firestore.collection('active_routes').doc(routeDoc).collection('drivers').doc(user.uid);
          await docRef.set({
            'driverId': user.uid,
            'routeName': routeName,
            'driverRoute': pointsPayload,
            'routePoints': pointsPayload,
            'updatedAt': FieldValue.serverTimestamp(),
          });
          debugPrint('Published active route for user ${user.uid} under $routeDoc');
        } else {
        // Inform the driver that the route was saved locally but not published
        // because the driver is currently offline. Publishing will occur when
        // the driver toggles online (handled by _toggleOnlineStatus) or
        // you can opt to publish immediately even while offline.
        SnackbarService.show(context, 'Route saved locally. Go ONLINE to publish it to passengers.', duration: const Duration(seconds: 3));
        debugPrint('Driver ${user.uid} saved currentRoute "$routeName" but not published because _isOnline=false');
      }

      setState(() {
        _currentRouteSaved = routeName;
      });

      debugPrint('Saved current route for driver ${user.uid}: $routeName (published=${_isOnline})');
    } catch (e) {
      debugPrint('Error publishing active route: $e');
    }
  }

  /// Remove the active route document for the driver (used when going offline)
  Future<void> _removeActiveRouteForUser(String uid, {String? routeName}) async {
    try {
      // Determine which route doc to remove the driver's document from.
      final routeToUse = (routeName != null && routeName.isNotEmpty)
          ? routeName
          : ((_currentRouteSaved != null && _currentRouteSaved!.isNotEmpty) ? _currentRouteSaved! : _selectedRoute);
      if (routeToUse.isEmpty) {
        debugPrint('No route known to remove for user $uid');
        return;
      }
      final routeDoc = _routeDocIdFromName(routeToUse);
      final driverDocRef = _firestore.collection('active_routes').doc(routeDoc).collection('drivers').doc(uid);
      final driverDoc = await driverDocRef.get();
      if (driverDoc.exists) {
        await driverDocRef.delete();
        debugPrint('Removed active route driver doc for $uid under route $routeDoc');
      }
      // If no drivers remain under this route, remove the empty route document
      final remaining = await _firestore.collection('active_routes').doc(routeDoc).collection('drivers').limit(1).get();
      if (remaining.docs.isEmpty) {
        try {
          await _firestore.collection('active_routes').doc(routeDoc).delete();
          debugPrint('Deleted empty active route document $routeDoc');
        } catch (_) {}
      }
      // Do NOT delete users/{uid}.currentRoute here — keep the driver's
      // selected/currentRoute persisted so they can continue to see it.
    } catch (e) {
      debugPrint('Error removing active route for $uid: $e');
    }
  }

  String _routeDocIdFromName(String name) {
    // Basic sanitization for Firestore doc id: remove slashes and trim
    var id = name.replaceAll('/', '_');
    id = id.replaceAll('\u200b', ''); // strip zero-width
    id = id.trim();
    if (id.isEmpty) id = 'route_${DateTime.now().millisecondsSinceEpoch}';
    return id;
  }

  @override
  Widget build(BuildContext context) {
    return SharedHome(
      key: _sharedHomeKey,
      roleLabel: 'TSUPERHERO',
      onSignOut: _handleSignOut,
      roleMenu: _buildDriverMenu(),
      roleActions: _buildDriverActions(),
      // Provide SharedHome with a callback so its bottom panel can toggle online
      // state on behalf of the driver (when the close button is tapped).
      onDriverToggleOnline: _toggleOnlineStatus,
      isDriverOnline: _isOnline,
      roleContentBuilder: (context, role, userLoc, onMapTap) => _buildDriverContent(context, role, userLoc, onMapTap),
      centerAction: Builder(builder: (context) {
        return ElevatedButton.icon(
          onPressed: () async {
            await _toggleOnlineStatus();
            // SharedHome will open/close the bottom panel based on the
            // `isDriverOnline` property passed into it; do not toggle here.
          },
          style: ElevatedButton.styleFrom(
            elevation: 8,
            backgroundColor: _isOnline ? Colors.green : Colors.grey,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          ),
          icon: Icon(_isOnline ? Icons.power_settings_new : Icons.play_arrow, color: Colors.white),
          label: Text(_isOnline ? 'Go Offline' : 'Go Online', style: const TextStyle(color: Colors.white, fontSize: 15)),
        );
      }),
    );
  }

  Widget _buildDriverContent(BuildContext sharedContext, String? role, LatLng? userLoc, void Function(LatLng)? onMapTap) {
    // Capture the descendant context so async callbacks can call SharedHome.of(...)
    _sharedHomeContext = sharedContext;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Earnings Section
        _buildEarningsSection(),

        // Status and Passenger Counter
        Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              // Online Status
              Text(
                _isOnline ? "🟢 ONLINE - VISIBLE TO PASSENGERS" : "🔴 OFFLINE",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: _isOnline ? Colors.green : Colors.red,
                ),
              ),
              const SizedBox(height: 16),

              // Passenger Counter
              const Text(
                'Passenger Counter',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Decrement Button
                  IconButton(
                    onPressed: _decrementPassengers,
                    icon: const Icon(Icons.remove_circle_outline),
                    color: Colors.red,
                    iconSize: 32,
                  ),

                  // Passenger Count Display
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      color: _currentPassengers >= _maxCapacity
                          ? Colors.red.withOpacity(0.1)
                          : Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _currentPassengers >= _maxCapacity
                            ? Colors.red
                            : Colors.green,
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(
                          '$_currentPassengers',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '/$_maxCapacity',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Increment Button
                  IconButton(
                    onPressed: _incrementPassengers,
                    icon: const Icon(Icons.add_circle_outline),
                    color: Colors.green,
                    iconSize: 32,
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // Capacity Warning
              if (_currentPassengers >= _maxCapacity)
                Text(
                  '⚠️ Capacity reached!',
                  style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),

              // Capacity Editor
              TextButton(
                onPressed: _showCapacityEditor,
                child: const Text('Adjust Maximum Capacity'),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Control Buttons
        Column(
          children: [
            ElevatedButton.icon(
              onPressed: _toggleOnlineStatus,
              style: ElevatedButton.styleFrom(
                elevation: 7,
                backgroundColor: _isOnline
                    ? Colors.green
                    : Colors.grey,
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
              ),
              icon: Icon(
                _isOnline ? Icons.power_settings_new : Icons.play_arrow,
                color: Colors.white,
              ),
              label: Text(
                _isOnline ? 'Go Offline' : 'Go Online',
                style: const TextStyle(color: Colors.white, fontSize: 15),
              ),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: () async {
                final sharedHome = _getSharedHomeState();
                if (sharedHome != null) {
                  await sharedHome.centerOnJeepMarker();
                } else {
                  debugPrint("SharedHome not found in context");
                }
              },
              child: const Text("Center Map on My Jeep"),
            ),
          ],
        ),

        // BaryaBox Status
        const SizedBox(height: 20),
        _trackerId != null
            ? Text(
          '📍 Tracking via BaryaBox: $_trackerId',
          style: const TextStyle(
            fontSize: 12,
            color: Colors.green,
            fontWeight: FontWeight.w500,
          ),
          textAlign: TextAlign.center,
        )
            : const Text(
          '❌ No BaryaBox connected',
          style: TextStyle(
            fontSize: 12,
            color: Colors.red,
            fontWeight: FontWeight.w500,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  List<Widget> _buildDriverMenu() => [
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
      // ADD TO BOTH FILES IN _buildPasaheroMenu() AND _buildDriverMenu()

  List<Widget> _buildDriverActions() => [
    // Wrap the actions in a scrollable area so the bottom panel won't overflow
    // on smaller screens. SharedHome places roleActions inside a constrained
    // bottom panel; making this scrollable prevents RenderOverflow.
    Builder(builder: (context) {
      final screenH = UIUtils.screenHeight(context);
      final bottomPanelHeight = math.min(screenH * 0.55, 380.0);
      // Reserve some space for the panel handle area and paddings
      final contentMaxHeight = (bottomPanelHeight - 72).clamp(120.0, bottomPanelHeight);
      return ConstrainedBox(
        constraints: BoxConstraints(maxHeight: contentMaxHeight),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
          child: Column(
            children: [
        Row(
          children: [
            // Passenger suggestion area - horizontal, bounded height (responsive)
            Expanded(
              child: Builder(
                builder: (context) {
                  // Mirror SharedHome's bottomPanelHeight calculation so this area
                  // adapts to the available panel space and avoids overflow.
                  final screenH = UIUtils.screenHeight(context);
                  final bottomPanelHeight = math.min(screenH * 0.55, 380.0);
                  // Allocate a fraction of bottom panel for the suggestion row.
                  final suggestionHeight = math.max(64.0, math.min(bottomPanelHeight * 0.30, 120.0));

                  return SizedBox(
                    height: suggestionHeight,
                    child: StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('para_requests')
                          .where('status', isEqualTo: 'pending')
                          .snapshots(),
                      builder: (context, snapshot) {
                        // Scale card width proportionally to suggestion height so the
                        // layout remains balanced on different screen sizes.
                        final baseCardWidth = UIUtils.responsiveCardWidth(context, fraction: 0.30, maxPx: 180.0);
                        final scale = (suggestionHeight / 120.0).clamp(0.6, 1.0);
                        // Increase passenger suggestion box size by 20% as requested.
                        final increasedFactor = 1.2;
                        final rawCard = baseCardWidth * scale * increasedFactor;
                        // Clamp to a sensible maximum (1.2x the configured maxPx)
                        final cardWidth = rawCard.clamp(48.0, 180.0 * increasedFactor);

                        if (!snapshot.hasData) {
                          return const Center(child: CircularProgressIndicator());
                        }

                        final docs = snapshot.data!.docs;
                        // Filter requests that are reasonably close to driver (if we have tracker)
                        final nearby = <QueryDocumentSnapshot>[];
                        for (final d in docs) {
                          final data = d.data() as Map<String, dynamic>;
                          if (data['passengerLocation'] != null && _jeepMarker != null) {
                            final GeoPoint gp = data['passengerLocation'];
                            final dist = _distanceKm(LatLng(gp.latitude, gp.longitude), _jeepMarker!.position);
                            if (dist <= 5.0) {
                              nearby.add(d);
                              continue;
                            }
                          }
                          // fallback: include anyway
                          nearby.add(d);
                        }

                        if (nearby.isEmpty) {
                          return SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(children: [
                              _buildPassengerPlaceholder(cardWidth),
                              _buildPassengerPlaceholder(cardWidth * 0.9),
                            ]),
                          );
                        }

                        return ListView(
                          scrollDirection: Axis.horizontal,
                          children: nearby.take(6).map((d) {
                            final data = d.data() as Map<String, dynamic>;
                            final id = d.id;
                            double? distKm;
                            if (data['passengerLocation'] != null && _jeepMarker != null) {
                              final gp = data['passengerLocation'] as GeoPoint;
                              distKm = _distanceKm(LatLng(gp.latitude, gp.longitude), _jeepMarker!.position);
                            }

                            return GestureDetector(
                              onTap: () {
                                // Driver taps passenger card - show info
                                SnackbarService.show(context, 'Selected request $id');
                              },
                              child: Container(
                                width: cardWidth,
                                margin: const EdgeInsets.only(right: 8, top: 6, bottom: 6),
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.06),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Req $id', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 6),
                                    Text(data['passengerName'] ?? 'Passenger', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                                    const SizedBox(height: 6),
                                    Text(distKm != null ? '${distKm.toStringAsFixed(1)} km' : 'Calculating', style: const TextStyle(color: Colors.greenAccent, fontSize: 12)),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
            // Fare / small action button placeholder
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: const [
                  Icon(Icons.attach_money, color: Colors.white),
                  SizedBox(height: 4),
                  Text('Fare', style: TextStyle(color: Colors.white)),
                ],
              ),
            ),
          ],
        ),


        // Seat management meter
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Seats', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold
              ,height: 1)
              
              ),
              // Large, easy-to-tap +/- buttons for adjusting passenger count
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 1.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Decrement button
                    ElevatedButton(
                      onPressed: _decrementPassengers,
                      style: ElevatedButton.styleFrom(
                        shape: const CircleBorder(),
                        minimumSize: const Size(64, 64),
                        padding: const EdgeInsets.all(0),
                        backgroundColor: Colors.redAccent,
                        elevation: 6,
                      ),
                      child: const Icon(Icons.remove, size: 36, color: Colors.white),
                    ),

                    const SizedBox(width: 10),

                    // Passenger count display
                    GestureDetector(
                      onTap: _showCapacityEditor,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          children: [
                            Text('$_currentPassengers', style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Text('/ $_maxCapacity', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(width: 20),

                    // Increment button
                    ElevatedButton(
                      onPressed: _incrementPassengers,
                      style: ElevatedButton.styleFrom(
                        shape: const CircleBorder(),
                        minimumSize: const Size(64, 64),
                        padding: const EdgeInsets.all(0),
                        backgroundColor: Colors.green,
                        elevation: 6,
                      ),
                      child: const Icon(Icons.add, size: 36, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Destination / Route selector (wrapped with dropdown)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          child: Column(
            children: [
              GestureDetector(
                onTap: () {
                  setState(() {
                    _showRouteMenu = !_showRouteMenu;
                  });
                },
                child: Column(
                  children: [
                    DestinationDisplay(roleLabel: 'TSUPERHERO', selectedRoute: _selectedRoute),
                    // Confirm Route button appears when a route is selected but not yet confirmed
                    if (_selectedRoute.isNotEmpty && _currentRouteSaved != _selectedRoute)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Row(
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () async {
                                  // Confirm route: publish to Firestore and keep it saved
                                  await _publishActiveRoute(_selectedRoute);
                                  SnackbarService.show(context, 'Route confirmed: $_selectedRoute');
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 12.0),
                                  child: Text('Confirm Route', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              if (_showRouteMenu)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: _presetRoutes.map((r) {
                      return ListTile(
                        dense: true,
                        title: Text(r, style: const TextStyle(color: Colors.white)),
                        onTap: () async {
                              setState(() {
                                _selectedRoute = r;
                                _showRouteMenu = false;
                              });
                              SnackbarService.show(context, 'Selected route: $r');
                              // If driver is online and a different route was previously
                              // published, remove that previous active route so it no
                              // longer appears to passengers.
                              try {
                                final user = _auth.currentUser;
                                if (user != null && _isOnline) {
                                  final prev = (_currentRouteSaved != null && _currentRouteSaved!.isNotEmpty) ? _currentRouteSaved! : null;
                                  if (prev != null && prev != r) {
                                    await _removeActiveRouteForUser(user.uid, routeName: prev);
                                  }
                                }
                              } catch (e) {
                                debugPrint('Tsuper: failed removing previous route on select: $e');
                              }
                              // Load route points from Firestore and display polyline
                              await _loadRoutePointsForName(r);
                            },
                      );
                    }).toList(),
                  ),
                ),
            ],
          ),
        ),
        ],
      ),
        ),
    );
  }
    ),
  ];

  // Helper: build a placeholder passenger card
  Widget _buildPassengerPlaceholder(double width) {
    return Container(
      width: width,
      margin: const EdgeInsets.only(right: 8, top: 6, bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          SizedBox(height: 8),
          Text('Passenger', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          SizedBox(height: 6),
          Text('Waiting', style: TextStyle(color: Colors.white70, fontSize: 12)),
          SizedBox(height: 6),
          Text('– km', style: TextStyle(color: Colors.greenAccent, fontSize: 12)),
        ],
      ),
    );
  }

  double _degToRad(double deg) => deg * math.pi / 180;
  double _distanceKm(LatLng a, LatLng b) {
    const R = 6371;
    final dLat = _degToRad(b.latitude - a.latitude);
    final dLon = _degToRad(b.longitude - a.longitude);
    final aVal = math.sin(dLat / 2) * math.sin(dLat / 2) + math.cos(_degToRad(a.latitude)) * math.cos(_degToRad(b.latitude)) * math.sin(dLon / 2) * math.sin(dLon / 2);
    return R * 2 * math.atan2(math.sqrt(aVal), math.sqrt(1 - aVal));
  }

  Future<void> _handleSignOut() async {
    await _auth.signOut();
    await _trackerSub?.cancel();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
    );
  }

  // Add this method to your existing TsuperheroHome class
  Future<void> _loadUserDisplayName() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final doc = await _firestore.collection('users').doc(user.uid).get();
      if (doc.exists) {
        final data = doc.data()!;

        // ✅ FIXED: Format as "FirstName L." (Last Name Initial)
        String formattedName = 'Driver';

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
        }

        // Update display name in state
        setState(() {
          _displayName = formattedName;
        });
      }
    } catch (e) {
      debugPrint('Error loading user name: $e');
    }
  }
}