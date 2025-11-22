// lib/pages/home/pasahero_home.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:para2/pages/home/shared_home.dart';
import 'package:para2/services/location_broadcast.dart';
import 'package:para2/pages/login/login.dart';
import 'package:para2/pages/login/qr_scan_page.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'dart:math' as math;
import 'dart:io';
import 'package:para2/theme/app_icons.dart';
import 'package:para2/pages/settings/profile_settings.dart';
import 'package:para2/services/RealtimeDatabaseService.dart';
import 'package:para2/services/button_actions.dart';
import 'package:para2/services/snackbar_service.dart';
import 'package:para2/services/map_theme_service.dart';
import 'package:para2/services/ui_utils.dart';
import 'package:para2/services/route_utils.dart';
import 'package:para2/widgets/compact_ads_button.dart';
import 'package:para2/pages/biyahe/biyahe_logs_page.dart';
import 'package:para2/widgets/destination_display.dart';

class PasaheroHome extends StatefulWidget {
  const PasaheroHome({super.key});
  

  @override
  State<PasaheroHome> createState() => _PasaheroHomeState();
}

class _PasaheroHomeState extends State<PasaheroHome> with WidgetsBindingObserver {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final RealtimeDatabaseService _rtdbService = RealtimeDatabaseService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  LatLng? _destination;
  LatLng? _userLoc;
  String? _selectedJeepId;

  bool _hasSetDestination = false;
  bool _hasSelectedJeep = false;
  // _isFollowing removed; follow handled by FollowService / SharedHome
  bool _showHint = true;
  bool _isLocationInitialized = false;
  bool _isProfileIncomplete = false;

  Map<String, Map<String, dynamic>> _jeepneys = {};
  StreamSubscription? _rtdbStream;
  StreamSubscription<Position>? _positionStream;
  final Set<Polyline> _polylines = {};
  // Keep last signature to avoid re-sending identical polylines (prevents blinking)
  String? _lastExternalPolylinesSignature;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _activeRoutesSub;
  // Active drivers discovered via Firestore `active_routes/{route}/drivers/{uid}`
  // keyed by driver uid. Each entry contains: points (List<LatLng>), plate, fullName, routeDoc
  final Map<String, Map<String, dynamic>> _activeDrivers = {};

  // Google Directions / polyline helper
  static const String _googleApiKey = 'AIzaSyCb4q7iicIT4TD8qjPQxHtlxYn4tEj4WOY';
  late final PolylinePoints _polylinePoints;

  // Route matching variables
  final double _routeMatchingThreshold = 2.0;

  // PASAHERO PARA! button animation state
  double _paraScalePasahero = 1.0;
  bool _paraPressedPasahero = false;
  // Original gradient colors
  final Color _paraGradientStartPasahero = const Color.fromARGB(255, 60, 14, 97);
  final Color _paraGradientEndPasahero = const Color.fromARGB(255, 24, 64, 150);
  // Brighter variants used when pressed
  final Color _paraGradientStartActivePasahero = const Color.fromARGB(255, 85, 14, 218);
  final Color _paraGradientEndActivePasahero = const Color.fromARGB(255, 4, 35, 77);

  

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // init polyline helper
    _polylinePoints = PolylinePoints();
    _initUserLocation();
    _checkProfileCompletion();
    _subscribeActiveRoutes();
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
    _activeRoutesSub?.cancel();
    super.dispose();
  }

  // Subscribe to Firestore `active_routes` and build a compact list of
  // active drivers whose published route overlaps the user's destination.
  void _subscribeActiveRoutes() {
    try {
      _activeRoutesSub?.cancel();
      _activeRoutesSub = FirebaseFirestore.instance.collection('active_routes').snapshots().listen((snap) async {
        if (!mounted) return;
        final Map<String, Map<String, dynamic>> found = {};

        // Get the passenger's own destination route points (if available)
        List<LatLng>? myRoutePoints;
        try {
          final destPoly = _polylines.firstWhere((p) => p.polylineId.value == 'destinationRoute', orElse: () => Polyline(polylineId: const PolylineId('__none'), points: []));
          if (destPoly.points.isNotEmpty) myRoutePoints = destPoly.points;
        } catch (_) {
          myRoutePoints = null;
        }

        for (final routeDoc in snap.docs) {
          try {
            // Some drivers may publish as a subcollection under a route doc
            // (active_routes/{routeDoc}/drivers/{uid}). Others may publish
            // directly under active_routes/{uid} (single-driver doc). Support
            // both shapes.
            final docData = routeDoc.data();
            // If this document itself looks like a driver record (has geo fields),
            // treat it as a single-driver doc where the doc ID is the driver's UID.
            bool handledDirectDoc = false;
            final directCandidateKeys = ['points', 'driverRoute', 'routePoints', 'route', 'polyline', 'active_segment'];
            bool looksLikeDriverDoc = false;
            for (final k in directCandidateKeys) {
              if (docData.containsKey(k) && docData[k] != null) {
                looksLikeDriverDoc = true;
                break;
              }
            }
            if (looksLikeDriverDoc) {
              debugPrint('active_routes: direct-driver-doc=${routeDoc.id}');
              final data = docData;
              final uid = routeDoc.id;
              final driversList = <MapEntry<String, Map<String, dynamic>>>[MapEntry(uid, data)];
              // process this single pseudo-driver entry below using the same loop
              for (final entry in driversList) {
                final ddocId = entry.key;
                final data = entry.value;
                final uid = ddocId;
                // Drivers may publish their route under different keys. Collect
                // all candidate arrays/maps and merge into a single pts list.
                final pts = <LatLng>[];
                final candidateKeys = ['points', 'driverRoute', 'routePoints', 'route', 'polyline', 'active_segment'];
                for (final key in candidateKeys) {
                  final rawPoints = data[key];
                  if (rawPoints == null) continue;
                  try {
                    if (rawPoints is List) {
                      for (final p in rawPoints) {
                        if (p is GeoPoint) pts.add(LatLng(p.latitude, p.longitude));
                        else if (p is Map) {
                          final latCand = p['lat'] ?? p['latitude'] ?? p['latitude_deg'];
                          final lngCand = p['lng'] ?? p['longitude'] ?? p['longitude_deg'];
                          final lat = (latCand is num) ? latCand.toDouble() : double.tryParse(latCand?.toString() ?? '');
                          final lng = (lngCand is num) ? lngCand.toDouble() : double.tryParse(lngCand?.toString() ?? '');
                          if (lat != null && lng != null) pts.add(LatLng(lat, lng));
                        } else if (p is List && p.length >= 2) {
                          final a = p[0];
                          final b = p[1];
                          final lat = (a is num) ? a.toDouble() : double.tryParse(a?.toString() ?? '');
                          final lng = (b is num) ? b.toDouble() : double.tryParse(b?.toString() ?? '');
                          if (lat != null && lng != null) pts.add(LatLng(lat, lng));
                        }
                      }
                    } else if (rawPoints is Map) {
                      final entries = rawPoints.entries.toList()..sort((a, b) => a.key.toString().compareTo(b.key.toString()));
                      for (final e in entries) {
                        final p = e.value;
                        if (p is GeoPoint) pts.add(LatLng(p.latitude, p.longitude));
                        else if (p is Map) {
                          final latCand = p['lat'] ?? p['latitude'] ?? p['latitude_deg'];
                          final lngCand = p['lng'] ?? p['longitude'] ?? p['longitude_deg'];
                          final lat = (latCand is num) ? latCand.toDouble() : double.tryParse(latCand?.toString() ?? '');
                          final lng = (lngCand is num) ? lngCand.toDouble() : double.tryParse(lngCand?.toString() ?? '');
                          if (lat != null && lng != null) pts.add(LatLng(lat, lng));
                        }
                      }
                    }
                  } catch (_) {}
                  try {
                    if (rawPoints is String && rawPoints.isNotEmpty) {
                      final decoded = _polylinePoints.decodePolyline(rawPoints);
                      for (final dp in decoded) pts.add(LatLng(dp.latitude, dp.longitude));
                    }
                  } catch (_) {}
                }

                // Decide inclusion below (same as original loop)
                bool include = true;
                bool overlapFound = false;
                if (myRoutePoints != null && myRoutePoints.isNotEmpty && pts.isNotEmpty) {
                  final overlap = findLastOverlappingNode(myRoutePoints, pts, toleranceMeters: _routeMatchingThreshold * 6.0);
                  overlapFound = overlap != null;
                  include = overlapFound;
                  debugPrint('  driver=$uid pts=${pts.length} myRoute=${myRoutePoints.length} overlap=${overlapFound}');
                  if (!include) {
                    final prox = _anyPointWithinMeters(myRoutePoints, pts, 30.0);
                    if (prox) {
                      include = true;
                      debugPrint('  driver=$uid included by proximity fallback');
                    }
                  }
                } else if (_hasSetDestination && (myRoutePoints == null || myRoutePoints.isEmpty) && _destination != null && pts.isNotEmpty) {
                  final overlap = findLastOverlappingNode(pts, [_destination!], toleranceMeters: _routeMatchingThreshold * 10.0);
                  include = overlap != null;
                  if (!include) {
                    final prox = _anyPointWithinMeters(pts, [_destination!], 50.0);
                    if (prox) {
                      include = true;
                      debugPrint('  driver=$uid included by destination proximity fallback');
                    }
                  }
                }

                if (!include) continue;

                // Fetch driver info
                String plate = '';
                String fullName = '';
                try {
                  final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
                  if (userDoc.exists) {
                    final ud = userDoc.data() ?? {};
                    plate = (ud['plateNumber'] ?? ud['plate'] ?? '').toString();
                    final first = (ud['firstName'] ?? '').toString();
                    final last = (ud['lastName'] ?? '').toString();
                    if (first.isNotEmpty && last.isNotEmpty) fullName = '$first $last';
                    else if ((ud['displayName'] ?? '').toString().isNotEmpty) fullName = ud['displayName'];
                  }
                } catch (e) {
                  debugPrint('Error fetching user $uid: $e');
                }

                LatLng rep = pts.isNotEmpty ? pts.first : const LatLng(0, 0);
                if (_userLoc != null && pts.isNotEmpty) {
                  double best = double.infinity;
                  for (final p in pts) {
                    final d = _distanceBetweenPointsMeters(p, _userLoc!);
                    if (d < best) {
                      best = d;
                      rep = p;
                    }
                  }
                }

                found[uid] = {
                  'uid': uid,
                  'points': pts,
                  'plate': plate,
                  'fullName': fullName,
                  'lat': rep.latitude,
                  'lng': rep.longitude,
                  'routeDoc': routeDoc.id,
                };
              }
              handledDirectDoc = true;
            }
            if (handledDirectDoc) continue;

            // Otherwise, expect a 'drivers' subcollection under this route doc
            final drivers = await FirebaseFirestore.instance.collection('active_routes').doc(routeDoc.id).collection('drivers').get();
            debugPrint('active_routes: doc=${routeDoc.id} drivers=${drivers.docs.length}');
            for (final ddoc in drivers.docs) {
              final data = ddoc.data();
              final uid = ddoc.id;
              // Drivers may publish their route under different keys. Collect
              // all candidate arrays/maps and merge into a single pts list.
              final pts = <LatLng>[];
              final candidateKeys = ['points', 'driverRoute', 'routePoints', 'route', 'polyline', 'active_segment'];
              for (final key in candidateKeys) {
                final rawPoints = data[key];
                if (rawPoints == null) continue;
                try {
                  if (rawPoints is List) {
                    for (final p in rawPoints) {
                      if (p is GeoPoint) pts.add(LatLng(p.latitude, p.longitude));
                      else if (p is Map) {
                        final latCand = p['lat'] ?? p['latitude'] ?? p['latitude_deg'];
                        final lngCand = p['lng'] ?? p['longitude'] ?? p['longitude_deg'];
                        final lat = (latCand is num) ? latCand.toDouble() : double.tryParse(latCand?.toString() ?? '');
                        final lng = (lngCand is num) ? lngCand.toDouble() : double.tryParse(lngCand?.toString() ?? '');
                        if (lat != null && lng != null) pts.add(LatLng(lat, lng));
                      } else if (p is List && p.length >= 2) {
                        final a = p[0];
                        final b = p[1];
                        final lat = (a is num) ? a.toDouble() : double.tryParse(a?.toString() ?? '');
                        final lng = (b is num) ? b.toDouble() : double.tryParse(b?.toString() ?? '');
                        if (lat != null && lng != null) pts.add(LatLng(lat, lng));
                      }
                    }
                  } else if (rawPoints is Map) {
                    final entries = rawPoints.entries.toList()..sort((a, b) => a.key.toString().compareTo(b.key.toString()));
                    for (final e in entries) {
                      final p = e.value;
                      if (p is GeoPoint) pts.add(LatLng(p.latitude, p.longitude));
                      else if (p is Map) {
                        final latCand = p['lat'] ?? p['latitude'] ?? p['latitude_deg'];
                        final lngCand = p['lng'] ?? p['longitude'] ?? p['longitude_deg'];
                        final lat = (latCand is num) ? latCand.toDouble() : double.tryParse(latCand?.toString() ?? '');
                        final lng = (lngCand is num) ? lngCand.toDouble() : double.tryParse(lngCand?.toString() ?? '');
                        if (lat != null && lng != null) pts.add(LatLng(lat, lng));
                      }
                    }
                  }
                } catch (_) {}
                // Also handle encoded polyline strings commonly used by Directions
                try {
                  if (rawPoints is String && rawPoints.isNotEmpty) {
                    // decode encoded polyline string to points
                    final decoded = _polylinePoints.decodePolyline(rawPoints);
                    for (final dp in decoded) {
                      pts.add(LatLng(dp.latitude, dp.longitude));
                    }
                  }
                } catch (_) {}
              }

              // Decide whether to include this driver: if the passenger has a
              // destination route polyline, include only drivers whose route
              // polyline overlaps with the passenger's polyline. If no
              // destination route is present, include all drivers.
              bool include = true;
              bool overlapFound = false;
              if (myRoutePoints != null && myRoutePoints.isNotEmpty && pts.isNotEmpty) {
                final overlap = findLastOverlappingNode(myRoutePoints, pts, toleranceMeters: _routeMatchingThreshold * 6.0);
                overlapFound = overlap != null;
                include = overlapFound;
                debugPrint('  driver=$uid pts=${pts.length} myRoute=${myRoutePoints.length} overlap=${overlapFound}');
                // If overlap failed, attempt a quick proximity fallback
                if (!include) {
                  final prox = _anyPointWithinMeters(myRoutePoints, pts, 30.0);
                  if (prox) {
                    include = true;
                    debugPrint('  driver=$uid included by proximity fallback');
                  }
                }
              } else if (_hasSetDestination && (myRoutePoints == null || myRoutePoints.isEmpty) && _destination != null && pts.isNotEmpty) {
                // Fallback: if we don't yet have the Directions polyline but
                // the passenger has a raw destination point, check proximity
                // of the driver's route to that single destination point.
                final overlap = findLastOverlappingNode(pts, [_destination!], toleranceMeters: _routeMatchingThreshold * 10.0);
                include = overlap != null;
                if (!include) {
                  final prox = _anyPointWithinMeters(pts, [_destination!], 50.0);
                  if (prox) {
                    include = true;
                    debugPrint('  driver=$uid included by destination proximity fallback');
                  }
                }
              }

              if (!include) continue;

              // Fetch driver user info (plate, name) if available
              String plate = '';
              String fullName = '';
              try {
                final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
                if (userDoc.exists) {
                  final ud = userDoc.data() ?? {};
                  plate = (ud['plateNumber'] ?? ud['plate'] ?? '').toString();
                  final first = (ud['firstName'] ?? '').toString();
                  final last = (ud['lastName'] ?? '').toString();
                  if (first.isNotEmpty && last.isNotEmpty) fullName = '$first $last';
                  else if ((ud['displayName'] ?? '').toString().isNotEmpty) fullName = ud['displayName'];
                }
              } catch (e) {
                debugPrint('Error fetching user $uid: $e');
              }

              // Representative location for UI/ETA: nearest point on route to user loc, or first point
              LatLng rep = pts.isNotEmpty ? pts.first : const LatLng(0, 0);
              if (_userLoc != null && pts.isNotEmpty) {
                double best = double.infinity;
                for (final p in pts) {
                  final d = _distanceBetweenPointsMeters(p, _userLoc!);
                  if (d < best) {
                    best = d;
                    rep = p;
                  }
                }
              }

              found[uid] = {
                'uid': uid,
                'points': pts,
                'plate': plate,
                'fullName': fullName,
                'lat': rep.latitude,
                'lng': rep.longitude,
                'routeDoc': routeDoc.id,
              };
            }
          } catch (e) {
            debugPrint('Error reading drivers for ${routeDoc.id}: $e');
            continue;
          }
        }

        if (!mounted) return;
        setState(() {
          _activeDrivers
            ..clear()
            ..addAll(found);
        });
      }, onError: (e) {
        debugPrint('active_routes subscription error: $e');
      });
    } catch (e) {
      debugPrint('Could not subscribe to active_routes: $e');
    }
  }

  // One-time rescan of active_routes. Useful to re-evaluate matches after
  // the passenger's destination route is built (so we don't miss drivers
  // because the initial snapshot arrived before the route polyline existed).
  Future<void> _rescanActiveRoutes() async {
    try {
      final snap = await FirebaseFirestore.instance.collection('active_routes').get();
      if (!mounted) return;
      // reuse logic from subscription: manually trigger the listener body
      // by reading each doc and processing drivers similarly.
      final Map<String, Map<String, dynamic>> found = {};

      List<LatLng>? myRoutePoints;
      try {
        final destPoly = _polylines.firstWhere((p) => p.polylineId.value == 'destinationRoute', orElse: () => Polyline(polylineId: const PolylineId('__none'), points: []));
        if (destPoly.points.isNotEmpty) myRoutePoints = destPoly.points;
      } catch (_) {
        myRoutePoints = null;
      }

      for (final routeDoc in snap.docs) {
        try {
          final drivers = await FirebaseFirestore.instance.collection('active_routes').doc(routeDoc.id).collection('drivers').get();
          debugPrint('rescan active_routes: doc=${routeDoc.id} drivers=${drivers.docs.length}');
          for (final ddoc in drivers.docs) {
            final data = ddoc.data();
            final uid = ddoc.id;
            final pts = <LatLng>[];
            final candidateKeys = ['points', 'driverRoute', 'routePoints', 'route', 'polyline', 'active_segment'];
            for (final key in candidateKeys) {
              final rawPoints = data[key];
              if (rawPoints == null) continue;
              try {
                if (rawPoints is List) {
                  for (final p in rawPoints) {
                    if (p is GeoPoint) pts.add(LatLng(p.latitude, p.longitude));
                    else if (p is Map) {
                      final latCand = p['lat'] ?? p['latitude'] ?? p['latitude_deg'];
                      final lngCand = p['lng'] ?? p['longitude'] ?? p['longitude_deg'];
                      final lat = (latCand is num) ? latCand.toDouble() : double.tryParse(latCand?.toString() ?? '');
                      final lng = (lngCand is num) ? lngCand.toDouble() : double.tryParse(lngCand?.toString() ?? '');
                      if (lat != null && lng != null) pts.add(LatLng(lat, lng));
                    } else if (p is List && p.length >= 2) {
                      final a = p[0];
                      final b = p[1];
                      final lat = (a is num) ? a.toDouble() : double.tryParse(a?.toString() ?? '');
                      final lng = (b is num) ? b.toDouble() : double.tryParse(b?.toString() ?? '');
                      if (lat != null && lng != null) pts.add(LatLng(lat, lng));
                    }
                  }
                } else if (rawPoints is Map) {
                  final entries = rawPoints.entries.toList()..sort((a, b) => a.key.toString().compareTo(b.key.toString()));
                  for (final e in entries) {
                    final p = e.value;
                    if (p is GeoPoint) pts.add(LatLng(p.latitude, p.longitude));
                    else if (p is Map) {
                      final latCand = p['lat'] ?? p['latitude'] ?? p['latitude_deg'];
                      final lngCand = p['lng'] ?? p['longitude'] ?? p['longitude_deg'];
                      final lat = (latCand is num) ? latCand.toDouble() : double.tryParse(latCand?.toString() ?? '');
                      final lng = (lngCand is num) ? lngCand.toDouble() : double.tryParse(lngCand?.toString() ?? '');
                      if (lat != null && lng != null) pts.add(LatLng(lat, lng));
                    }
                  }
                }
              } catch (_) {}
              try {
                if (rawPoints is String && rawPoints.isNotEmpty) {
                  final decoded = _polylinePoints.decodePolyline(rawPoints);
                  for (final dp in decoded) pts.add(LatLng(dp.latitude, dp.longitude));
                }
              } catch (_) {}
            }

            bool include = true;
            if (myRoutePoints != null && myRoutePoints.isNotEmpty && pts.isNotEmpty) {
              final overlap = findLastOverlappingNode(myRoutePoints, pts, toleranceMeters: _routeMatchingThreshold * 6.0);
              include = overlap != null || _anyPointWithinMeters(myRoutePoints, pts, 30.0);
            } else if (_hasSetDestination && (myRoutePoints == null || myRoutePoints.isEmpty) && _destination != null && pts.isNotEmpty) {
              final overlap = findLastOverlappingNode(pts, [_destination!], toleranceMeters: _routeMatchingThreshold * 10.0);
              include = overlap != null || _anyPointWithinMeters(pts, [_destination!], 50.0);
            }

            if (!include) continue;

            String plate = '';
            String fullName = '';
            try {
              final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
              if (userDoc.exists) {
                final ud = userDoc.data() ?? {};
                plate = (ud['plateNumber'] ?? ud['plate'] ?? '').toString();
                final first = (ud['firstName'] ?? '').toString();
                final last = (ud['lastName'] ?? '').toString();
                if (first.isNotEmpty && last.isNotEmpty) fullName = '$first $last';
                else if ((ud['displayName'] ?? '').toString().isNotEmpty) fullName = ud['displayName'];
              }
            } catch (e) {
              debugPrint('Error fetching user $uid: $e');
            }

            LatLng rep = pts.isNotEmpty ? pts.first : const LatLng(0, 0);
            if (_userLoc != null && pts.isNotEmpty) {
              double best = double.infinity;
              for (final p in pts) {
                final d = _distanceBetweenPointsMeters(p, _userLoc!);
                if (d < best) {
                  best = d;
                  rep = p;
                }
              }
            }

            found[uid] = {
              'uid': uid,
              'points': pts,
              'plate': plate,
              'fullName': fullName,
              'lat': rep.latitude,
              'lng': rep.longitude,
              'routeDoc': routeDoc.id,
            };
          }
        } catch (e) {
          debugPrint('Error reading drivers for ${routeDoc.id}: $e');
          continue;
        }
      }

      if (!mounted) return;
      setState(() {
        _activeDrivers
          ..clear()
          ..addAll(found);
      });
    } catch (e) {
      debugPrint('rescanActiveRoutes error: $e');
    }
  }

  // Haversine helper local to this file to avoid importing private helpers
  double _distanceBetweenPointsMeters(LatLng a, LatLng b) {
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

  // Return true if any point in list `a` is within `thresholdMeters` of any
  // point in list `b`.
  bool _anyPointWithinMeters(List<LatLng> a, List<LatLng> b, double thresholdMeters) {
    if (a.isEmpty || b.isEmpty) return false;
    for (final pa in a) {
      for (final pb in b) {
        if (_distanceBetweenPointsMeters(pa, pb) <= thresholdMeters) return true;
      }
    }
    return false;
  }

  // Helper to animate PASAHERO PARA! press and trigger action
  Future<void> _triggerPasaheroPara({bool longPress = false}) async {
    setState(() {
      _paraPressedPasahero = true;
      _paraScalePasahero = longPress ? 1.12 : 1.08;
    });

    try {
      if (!longPress) {
        await _sendParaSignal();
      }
    } catch (_) {}

    await Future.delayed(const Duration(milliseconds: 180));

    if (mounted) {
      setState(() {
        _paraScalePasahero = 1.0;
        _paraPressedPasahero = false;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    debugPrint('PasaheroHome lifecycle: $state');
    if (state == AppLifecycleState.resumed) {
      // Restart the position stream when app resumes
      _startPositionStream();
    } else if (state == AppLifecycleState.paused) {
      // Pause subscription to conserve resources; will be restarted on resume
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

      // Start a lifecycle-aware position stream
      await _startPositionStream();
    } catch (e) {
      debugPrint("Error initializing GPS: $e");
    }
  }

  /// Start position stream if not already started. This method guards
  /// against double subscriptions and logs updates/errors for debugging.
  Future<void> _startPositionStream() async {
    try {
      if (_positionStream != null) {
        // If paused, resume
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

      _positionStream = Geolocator.getPositionStream(locationSettings: settings)
          .listen((p) {
        debugPrint('Position stream update: ${p.latitude}, ${p.longitude}');
        _updateUserMarker(LatLng(p.latitude, p.longitude));
      }, onError: (err) {
        debugPrint('Position stream error: $err');
      }, onDone: () {
        debugPrint('Position stream done');
        _positionStream = null;
      });

      debugPrint('Position stream started');
    } catch (e) {
      debugPrint('Failed to start position stream: $e');
    }
  }

  // ✅ Enhanced location update with debugging
  void _updateUserMarker(LatLng pos) {
    if (pos.latitude == 0.0 && pos.longitude == 0.0) {
      debugPrint("⚠️ Invalid location (0,0) - skipping");
      return;
    }

    debugPrint("Pasahero Location Update: ${pos.latitude}, ${pos.longitude}");

    setState(() => _userLoc = pos);

    // Publish location to the app-wide broadcaster. SharedHome subscribes
    // to this stream and will update the map marker regardless of ancestor
    // lookup availability.
    try {
      final emitTs = DateTime.now().millisecondsSinceEpoch;
      debugPrint('emit_ts=$emitTs Publishing location: $pos');
      LocationBroadcast.instance.emit(pos);
      debugPrint('📍 Published location to LocationBroadcast: $pos');
    } catch (e) {
      debugPrint('❌ Failed to publish location: $e');
    }

    _updatePolyline();
    // If we have a destination, refresh the driving route polyline
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

      final shared = SharedHome.of(context);
      if (shared == null) return;

      // UPDATED CODE:
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
              'speed': speed ?? 0.0,
              'course': course ?? 0.0,
              'isOnline': isOnline,
              'currentPassengers': currentPassengers,
              'maxCapacity': maxCapacity,
              'hasAvailableSeats': currentPassengers < maxCapacity,
              'jeepneyPos': LatLng(lat, lng),
            };

            // ✅ ADDED: Create marker with zoom-aware icon
            final sharedHome = SharedHome.of(context);
            if (sharedHome != null) {
              // Use medium icon by default (will be updated by SharedHome's zoom logic)
              final marker = Marker(
                markerId: MarkerId('jeep_$id'),
                position: LatLng(lat, lng),
                icon: AppIcons.jeepIconMedium ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
                infoWindow: InfoWindow(
                  title: 'Jeepney $id',
                  snippet: 'Speed: ${(speed ?? 0.0).toStringAsFixed(1)} km/h | Passengers: $currentPassengers/$maxCapacity',
                ),
                rotation: course ?? 0.0,
                anchor: const Offset(0.5, 0.5),
                flat: true,
              );

              // Add marker to SharedHome for proper zoom handling
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

  // ✅ Enhanced Route Matching Logic
  bool _isJeepneyOnRoute(String jeepneyId) {
    if (_destination == null || _userLoc == null) return false;

    final jeepney = _jeepneys[jeepneyId];
    if (jeepney == null) return false;

    final jeepneyPos = LatLng((_toDouble(jeepney['lat']) ?? 0.0), (_toDouble(jeepney['lng']) ?? 0.0));

    // Simple route matching: check if jeepney is between user and destination
    final userToDestDistance = _distanceKm(_userLoc!, _destination!);
    final userToJeepDistance = _distanceKm(_userLoc!, jeepneyPos);
    final jeepToDestDistance = _distanceKm(jeepneyPos, _destination!);

    // Jeepney is considered "on route" if it's reasonably close to the path
    // between user and destination (using triangle inequality)
    final totalDirectDistance = userToDestDistance;
    final actualDistance = userToJeepDistance + jeepToDestDistance;

    // If actual distance is within threshold of direct distance, consider it on route
    return (actualDistance - totalDirectDistance) <= _routeMatchingThreshold;
  }

  // ✅ Distance and ETA helpers
  double _degToRad(double deg) => deg * math.pi / 180;
  double _distanceKm(LatLng a, LatLng b) {
    const R = 6371;
    final dLat = _degToRad(b.latitude - a.latitude);
    final dLon = _degToRad(b.longitude - a.longitude);
    final aVal =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
            math.cos(_degToRad(a.latitude)) *
                math.cos(_degToRad(b.latitude)) *
                math.sin(dLon / 2) *
                math.sin(dLon / 2);
    return R * 2 * math.atan2(math.sqrt(aVal), math.sqrt(1 - aVal));
  }

  double _computeETA(LatLng from, LatLng to, double speedKmh) {
    final dist = _distanceKm(from, to);
    if (speedKmh <= 0) return double.infinity;
    return (dist / speedKmh) * 60;
  }

  // ✅ Update lines connecting passenger, jeep, destination
  void _updatePolyline() {
    // Keep any previously-built route polyline (destinationRoute)
    // but remove transient tracking/destination lines so we can refresh them.
    _polylines.removeWhere((p) => p.polylineId.value == 'trackingLine' || p.polylineId.value == 'destinationLine');
    if (_userLoc == null) return;

    // If a road-following route polyline already exists, avoid adding the
    // straight destinationLine (user->destination) because it visually
    // duplicates the proper route. Only show destinationLine when no
    // destinationRoute is present.
    final bool hasRoutePolyline = _polylines.any((p) => p.polylineId.value == 'destinationRoute');

    if (_hasSelectedJeep &&
        _selectedJeepId != null &&
        _jeepneys[_selectedJeepId] != null) {
      final jeep = _jeepneys[_selectedJeepId]!;
      final jeepPos = LatLng((_toDouble(jeep['lat']) ?? 0.0), (_toDouble(jeep['lng']) ?? 0.0));
      _polylines.add(
        Polyline(
          polylineId: const PolylineId("trackingLine"),
          color: Colors.green,
          width: 4,
          points: [_userLoc!, jeepPos],
        ),
      );
    }

    if (_destination != null) {
      if (!hasRoutePolyline) {
        _polylines.add(
          Polyline(
            polylineId: const PolylineId("destinationLine"),
            color: Colors.blueAccent,
            width: 3,
            points: [_userLoc!, _destination!],
          ),
        );
      }
    }

    _maybePushExternalPolylines();
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

    // Build route polyline for the destination
    await _buildRoutePolyline();

    // Start listening to jeepneys after destination is set
    if (_rtdbStream == null) {
      _listenToJeepneys();
    }
  }

  // ✅ FIXED: Enhanced PARA! signal with profile completion check
  Future<void> _sendParaSignal() async {
    // Check profile completion first
    if (_isProfileIncomplete) {
      SnackbarService.show(context, '❌ Please complete your profile in Settings to use PARA!');
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
      SnackbarService.show(context, '❌ Selected jeepney is no longer available');
      return;
    }

    // Check capacity
    if (selectedJeep['hasAvailableSeats'] != true) {
      SnackbarService.show(context, '❌ Jeepney is full (${selectedJeep['currentPassengers']}/${selectedJeep['maxCapacity']})');
      return;
    }

    // Check route matching
    if (!_isJeepneyOnRoute(_selectedJeepId!)) {
      SnackbarService.show(context, '❌ Selected jeepney is not on your route');
      return;
    }

    setState(() {
      _hasSelectedJeep = false;
    });

    try {
      final baseFare = 15.00;
      final isDigitalPayment = true; // Demo - assume digital payment

      final docRef = await _firestore.collection('para_requests').add({
        'jeepneyId': _selectedJeepId,
        'passengerId': _auth.currentUser?.uid,
        'passengerName': _auth.currentUser?.displayName ?? 'Passenger',
        'passengerLocation': GeoPoint(_userLoc!.latitude, _userLoc!.longitude),
        'destination': GeoPoint(_destination!.latitude, _destination!.longitude),
        'status': 'pending',
        'timestamp': FieldValue.serverTimestamp(),
        'fare': baseFare,
        'paymentMethod': isDigitalPayment ? 'digital' : 'cash',
        'isDigitalPayment': isDigitalPayment,
      });

      SnackbarService.show(context, '🚍 PARA! signal sent to Jeepney $_selectedJeepId', duration: const Duration(seconds: 3));

      debugPrint("✅ PARA! request sent with ID: ${docRef.id}");

      // Reset selection
      setState(() {
        _selectedJeepId = null;
        _hasSelectedJeep = false;
      });

      _updatePolyline();

    } catch (e) {
      debugPrint("❌ Failed to send PARA! signal: $e");
      SnackbarService.show(context, '❌ Failed to send PARA! signal: $e', duration: const Duration(seconds: 3));
    }
  }

  // ✅ Enhanced jeepney suggestion list with route matching and capacity info
  Widget _buildJeepneySuggestionList({bool compact = false}) {
    // Always render the suggestion area. If destination is set we show
    // only jeepneys on-route; otherwise show nearby available jeepneys.
    // Merge RTDB jeepneys with Firestore-published active drivers.
    final Map<String, Map<String, dynamic>> combined = {};
    combined.addAll(_jeepneys);
    // Firestore drivers keyed with 'fs_<uid>' to avoid id collision
    _activeDrivers.forEach((uid, info) {
      combined['fs_$uid'] = {
        'lat': info['lat'] ?? 0.0,
        'lng': info['lng'] ?? 0.0,
        'currentPassengers': info['currentPassengers'] ?? 0,
        'maxCapacity': info['maxCapacity'] ?? 20,
        'hasAvailableSeats': true,
        'isOnline': true,
        'speed': _toDouble(info['speed']) ?? 20.0,
        // preserve parsed plate & name for display
        'plate': info['plate'] ?? '',
        'fullName': info['fullName'] ?? '',
        'source': 'firestore',
        'uid': uid,
      };
    });

    final availableJeepneys = combined.entries.where((entry) {
      final v = entry.value;
      final online = v['isOnline'] == true;
      final hasSeats = v['hasAvailableSeats'] == true;
      if (!online || !hasSeats) return false;
      if (_hasSetDestination) {
        // For RTDB entries, keep existing check; for Firestore entries use
        // the overlap result already computed in _activeDrivers.
        if (entry.key.startsWith('fs_')) return true;
        return _isJeepneyOnRoute(entry.key);
      }
      // No destination placed: show all online jeepneys with seats
      return true;
    }).toList();

    final showNoAvailableOnRoute = _hasSetDestination && availableJeepneys.isEmpty;

    Widget _buildPlaceholderCard({double width = 160}) {
      return Container(
        width: width,
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            SizedBox(height: 8),
            Text('Jeepney', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            SizedBox(height: 6),
            Text('Calculating', style: TextStyle(color: Colors.white70, fontSize: 12)),
            SizedBox(height: 6),
            Text('– seats', style: TextStyle(color: Colors.greenAccent, fontSize: 12)),
          ],
        ),
      );
    }

    // Compute responsive sizes using shared helpers
    final screenWidth = UIUtils.screenWidth(context);
    final cardWidthCompact = UIUtils.responsiveCardWidth(context, fraction: 0.45, maxPx: 180.0);
    final cardWidthFull = UIUtils.responsiveCardWidth(context, fraction: 0.6, maxPx: 220.0);

    // When compact is true we render a condensed widget suitable for a row
    if (compact) {
      // Render up to 2 items (or placeholders) in compact mode. If there are
      // no jeepneys on route we still show faded placeholders with an overlay
      // message.
      final items = <Widget>[];
          if (availableJeepneys.isNotEmpty) {
        for (final entry in availableJeepneys.take(2)) {
          final id = entry.key;
          final data = entry.value;
          LatLng jeepPos = LatLng((_toDouble(data['lat']) ?? 0.0), (_toDouble(data['lng']) ?? 0.0));
          double? eta;
            if (_userLoc != null) {
            eta = _computeETA(jeepPos, _userLoc!, _toDouble(data['speed']) ?? 20.0);
          }

          final currentPassengers = data['currentPassengers'] ?? 0;
          final maxCapacity = data['maxCapacity'] ?? 20;
          final availableSeats = maxCapacity - currentPassengers;

          items.add(GestureDetector(
            onTap: () {
              setState(() {
                _selectedJeepId = id;
                _hasSelectedJeep = true;
                _updatePolyline();
              });
              if (id.startsWith('fs_')) {
                final plate = (data['plate'] ?? '').toString();
                final name = (data['fullName'] ?? '').toString();
                final txt = plate.isNotEmpty ? '$plate and ${name.isNotEmpty ? name : 'Driver'}' : 'Selected driver ${id.substring(3)}';
                SnackbarService.show(context, '✅ $txt', duration: const Duration(seconds: 2));
              } else {
                SnackbarService.show(context, '✅ Selected Jeepney $id ($availableSeats seats available)', duration: const Duration(seconds: 1));
              }
            },
            child: Container(
              width: cardWidthCompact,
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Prefer displaying plate number and driver name (from Firestore)
                  Text(
                    (data['plate'] != null && data['plate'].toString().isNotEmpty)
                        ? '${data['plate']}${(data['fullName'] ?? '').toString().isNotEmpty ? ' • ${data['fullName']}' : ''}'
                        : 'Jeep $id',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  Text(eta != null && eta != double.infinity ? '${eta.toStringAsFixed(1)} min' : 'Calculating', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  const SizedBox(height: 6),
                  Text('$availableSeats seats', style: const TextStyle(color: Colors.greenAccent, fontSize: 12)),
                ],
              ),
            ),
          ));
        }
      } else {
        // placeholders (use responsive widths)
        items.addAll([_buildPlaceholderCard(width: cardWidthCompact), _buildPlaceholderCard(width: cardWidthCompact * 0.9)]);
      }

      final content = SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: items),
      );

      if (showNoAvailableOnRoute) {
        return SizedBox(
          width: screenWidth,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Opacity(opacity: 0.35, child: content),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: SizedBox(
                  width: screenWidth - 32,
                  child: const Text(
                    'No available jeepneys with seats on your route nearby.',
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
        );
      }

      return content;
    }

    // Default (full) layout - show full list or faded placeholders with overlay
    final container = Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Jeeps On Your Route",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 110,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: availableJeepneys.isNotEmpty
                  ? availableJeepneys.map((entry) {
                      final id = entry.key;
                      final data = entry.value;
                      LatLng jeepPos = LatLng((_toDouble(data['lat']) ?? 0.0), (_toDouble(data['lng']) ?? 0.0));
                      double? eta;
                      if (_userLoc != null) {
                        eta = _computeETA(jeepPos, _userLoc!, _toDouble(data['speed']) ?? 20.0);
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
                          if (id.startsWith('fs_')) {
                            final plate = (data['plate'] ?? '').toString();
                            final name = (data['fullName'] ?? '').toString();
                            final txt = plate.isNotEmpty ? '$plate and ${name.isNotEmpty ? name : 'Driver'}' : 'Selected driver ${id.substring(3)}';
                            SnackbarService.show(context, '✅ $txt', duration: const Duration(seconds: 2));
                          } else {
                            SnackbarService.show(context, '✅ Selected Jeepney $id ($availableSeats seats available)', duration: const Duration(seconds: 1));
                          }
                        },
                        child: Container(
                          width: cardWidthFull,
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                (data['plate'] != null && data['plate'].toString().isNotEmpty)
                                    ? '${data['plate']}${(data['fullName'] ?? '').toString().isNotEmpty ? ' • ${data['fullName']}' : ''}'
                                    : 'Jeep $id',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                              const SizedBox(height: 6),
                              Text(eta != null && eta != double.infinity ? '${eta.toStringAsFixed(1)} min' : 'Calculating', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                              const SizedBox(height: 6),
                              Text('$availableSeats seats', style: const TextStyle(color: Colors.greenAccent, fontSize: 12)),
                            ],
                          ),
                        ),
                      );
                    }).toList()
                  : [
                      _buildPlaceholderCard(width: cardWidthFull),
                      _buildPlaceholderCard(width: cardWidthFull),
                      _buildPlaceholderCard(width: cardWidthFull),
                    ],
            ),
          ),
        ],
      ),
    );

    if (showNoAvailableOnRoute) {
      return Stack(alignment: Alignment.center, children: [
        Opacity(opacity: 0.35, child: container),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0),
          child: const Text(
            'No available jeepneys with seats on your route nearby.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontSize: 14),
          ),
        ),
      ]);
    }

    return container;
  }

  // Info card helper removed - using inline overlays/placeholders instead


  // ✅ ADDED: Compact ads button for top-right
  Widget _buildCompactAdsButton() {
    return Positioned(
      top: 80,
      right: 16,
      child: CompactAdsButton(
        onPointsUpdate: () {
          // Refresh points if needed
          setState(() {});
        },
      ),
    );
  }

  List<Widget> _buildPasaheroMenu() => [
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

  List<Widget> _buildPasaheroActions() => [
    Column(
      children: [
            Row(
          children: [

            // Make the suggestion area expand to available width and scroll horizontally
            Expanded(
              child: SizedBox(
                height: 120,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: _buildJeepneySuggestionList(compact: true),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],),
        DestinationDisplay(roleLabel: "PASAHERO"),
            
        Container(
          width: double.infinity,
          child: Row(
            children: [
              Container(  
                
                padding: EdgeInsets.symmetric(horizontal: 17, vertical: 5),
                margin: EdgeInsets.only(right: 5,top: 10,bottom: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  gradient: LinearGradient(colors: const [
                    Color.fromARGB(255, 52, 63, 128),
                   Color.fromARGB(255, 90, 35, 134),
                  ],
                  ),
          
                ),
                child: Column(
                  children: [
                    Text('ABC XXX', style: TextStyle( 
                      height: 1,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    ),
                    Row(
                      children: [
                        Icon(Icons.person, color: Colors.white, size: 10,),
                        Text("Driver's Name", style: TextStyle( 
                          height: 1,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        ),
                      ],
                    ),
                  ],
                )
                ),
              Column(
                children: [
                  Container(
                    
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Destination:', style: TextStyle( 
                          height: 1,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: const Color.fromARGB(255, 196, 196, 196),
                        ),
                        textAlign: TextAlign.start,
                        ),
                        
                        Text("Approx. Fare", style: TextStyle( 
                          height: 1,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: const Color.fromARGB(255, 196, 196, 196),
                      
                        ),   
                        textAlign: TextAlign.left,
                        ),
                        Text("Jeep Route", style: TextStyle( 
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: const Color.fromARGB(255, 218, 218, 218),
                        ),   
                        textAlign: TextAlign.left,
                        ),
                        
                      ],
                    ),
                  )
                  
                ],
              ),
              Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('00 meters', style: TextStyle( 
                    height: 1,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  ), 
                  Text('00 Pesos', style: TextStyle( 
                    height: 1,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  ), 
                  Text('00 Pesos', style: TextStyle( 
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: const Color.fromARGB(0, 255, 255, 255),
                  ),
                  ), 

                ],
                
              )
            ],
          
          ),
        ),    
             
       GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) {
          setState(() {
            _paraScalePasahero = 1.08;
            _paraPressedPasahero = true;
          });
        },
        onTapUp: (_) {
          _triggerPasaheroPara(longPress: false);
        },
        onTapCancel: () {
          setState(() {
            _paraScalePasahero = 1.0;
            _paraPressedPasahero = false;
          });
        },
        onLongPress: () async {
          // keep visual and show cancel placeholder
          setState(() {
            _paraScalePasahero = 1.12;
            _paraPressedPasahero = true;
          });
          SnackbarService.show(context, '🚍 Cancel Ride(Placeholder)');
          await Future.delayed(const Duration(milliseconds: 220));
          if (mounted) {
            setState(() {
              _paraScalePasahero = 1.0;
              _paraPressedPasahero = false;
            });
          }
        },
         child: AnimatedScale(
          scale: _paraScalePasahero,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutBack,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 3,
                colors: [
                  (_paraPressedPasahero ? _paraGradientStartActivePasahero : _paraGradientStartPasahero),
                  (_paraPressedPasahero ? _paraGradientEndActivePasahero : _paraGradientEndPasahero),
                ],
              ),
              borderRadius: BorderRadius.circular(22),
            ),
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 5),
            child: Text('PARA!', style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 25,
              fontFamily: GoogleFonts.roboto().fontFamily,
              color: Colors.white
            ),
            ),
          ),
        ),
       )
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
      void Function(LatLng)? onTap,
      ) {
    if (userLoc != null && _userLoc == null) {
      _userLoc = userLoc;
    }

    _updatePolyline();

    return Stack(
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_showHint && _isLocationInitialized)
            _buildJeepneySuggestionList(),

          ],
        ),

        // ✅ ADDED: Compact ads button positioned in top-right
        _buildCompactAdsButton(),

      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return SharedHome(
      roleLabel: 'PASAHERO',
      onSignOut: _handleSignOut,
      roleMenu: _buildPasaheroMenu(),
      roleActions: _buildPasaheroActions(),
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

    _polylines.removeWhere((p) => p.polylineId.value == 'destinationRoute');

    final origin = PointLatLng(_userLoc!.latitude, _userLoc!.longitude);
    final dest = PointLatLng(_destination!.latitude, _destination!.longitude);

    debugPrint('buildRoutePolyline: requesting route $origin -> $dest');

    try {
      final result = await _polylinePoints.getRouteBetweenCoordinates(
        googleApiKey: _googleApiKey,
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

      final routePoints = result.points.map((p) => LatLng(p.latitude, p.longitude)).toList();

      setState(() {
        _polylines.add(Polyline(
          polylineId: const PolylineId('destinationRoute'),
          color: Colors.blue,
          width: 5,
          points: routePoints,
        ));
        // Ensure any straight destinationLine is removed so only the
        // road-following route remains visible.
        _polylines.removeWhere((p) => p.polylineId.value == 'destinationLine');
      });
      // Push updated polylines to SharedHome so map updates immediately.
      // Only push when the set actually changed to avoid flicker/blinking.
      _maybePushExternalPolylines();
      // Re-evaluate active_routes now that the destination route is available
      // so we don't miss drivers when the initial snapshot arrived earlier.
      _rescanActiveRoutes();
      debugPrint('buildRoutePolyline: route has ${routePoints.length} points');
    } catch (e) {
      debugPrint('buildRoutePolyline error: $e');
    }
  }

  // Compute a compact signature for the current external polylines so we
  // can skip re-sending identical data to SharedHome (which causes flicker).
  String _signatureForPolylines(Set<Polyline> polys) {
    final sb = StringBuffer();
    final sorted = polys.toList()..sort((a, b) => a.polylineId.value.compareTo(b.polylineId.value));
    for (final p in sorted) {
      sb.write(p.polylineId.value);
      sb.write(':');
      for (final pt in p.points) {
        // round to 6 decimals to avoid tiny float diffs
        sb.write(pt.latitude.toStringAsFixed(6));
        sb.write(',');
        sb.write(pt.longitude.toStringAsFixed(6));
        sb.write(';');
      }
      sb.write('|');
    }
    return sb.toString();
  }

  // Push external polylines to SharedHome only if they changed since last push
  void _maybePushExternalPolylines() {
    try {
      final sig = _signatureForPolylines(_polylines);
      if (sig == _lastExternalPolylinesSignature) return;
      _lastExternalPolylinesSignature = sig;
      SharedHome.of(context)?.setExternalPolylines(_polylines);
    } catch (e) {
      debugPrint('Error pushing external polylines: $e');
    }
  }
}