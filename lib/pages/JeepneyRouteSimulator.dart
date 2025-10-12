import 'dart:math';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:geolocator/geolocator.dart';

class PassengerMarker {
  final LatLng position;
  int distance;
  int groupSize;

  PassengerMarker({
    required this.position,
    required this.distance,
    required this.groupSize,
  });
}

class OSRMService {
  Future<List<LatLng>> getRoute(LatLng start, LatLng end) async {
    final response = await http.get(
      Uri.parse(
        'http://router.project-osrm.org/route/v1/driving/'
        '${start.longitude},${start.latitude};'
        '${end.longitude},${end.latitude}?overview=full&geometries=geojson',
      ),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to load route: ${response.statusCode}');
    }

    final data = json.decode(response.body);
    if (data['routes'] == null || data['routes'].isEmpty) {
      throw Exception('No route found');
    }

    final coords = data['routes'][0]['geometry']['coordinates'] as List;
    return coords.map<LatLng>((c) => LatLng(c[1], c[0])).toList();
  }
}

class JeepneyRouteSimulator extends StatefulWidget {
  const JeepneyRouteSimulator({super.key});

  @override
  State<JeepneyRouteSimulator> createState() => _JeepneyRouteSimulatorState();
}

class _JeepneyRouteSimulatorState extends State<JeepneyRouteSimulator> {
  final MapController _mapController = MapController();
  final OSRMService _osrmService = OSRMService();
  LatLng jeepneyPosition = const LatLng(14.5995, 120.9842);
  LatLng? destination;
  String destinationName = "Tap to set destination";
  List<LatLng> routePoints = [];
  List<PassengerMarker> passengers = [];
  bool isPanelUp = false;
  double panelHeight = 80.0;
  final double maxPanelHeight = 200.0;
  bool isLoading = false;
  bool routeConfirmed = false;
  final Random _random = Random();
  Offset? _dragPosition;
  bool _isDraggingJeepney = false;

  void _handleMapTap(TapPosition tapPosition, LatLng latLng) async {
    try {
      setState(() {
        isLoading = true;
        destination = latLng;
        passengers.clear();
        routeConfirmed = false;
      });

      await Future.delayed(const Duration(milliseconds: 500));
      final name = await _getLocationName(latLng);
      setState(() {
        destinationName = name;
        isLoading = false;
      });
      await _fetchRoute();
    } catch (e) {
      setState(() => isLoading = false);
      print("Map tap error: $e");
    }
  }

  Future<String> _getLocationName(LatLng latLng) async {
    try {
      final response = await http.get(
        Uri.parse(
          'https://nominatim.openstreetmap.org/reverse?format=json&lat=${latLng.latitude}&lon=${latLng.longitude}&zoom=16&addressdetails=1',
        ),
        headers: {'User-Agent': 'JeepneySimulator/1.0'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final address = data['address'] as Map<String, dynamic>?;
        return address?['road'] ??
            address?['neighbourhood'] ??
            "Nearby Location";
      }
    } catch (e) {
      print("Error getting location: $e");
    }
    return "Nearby Location";
  }

  Future<void> _fetchRoute() async {
    if (destination == null) return;

    setState(() => isLoading = true);
    try {
      final points = await _osrmService.getRoute(jeepneyPosition, destination!);
      setState(() => routePoints = points);
    } catch (e) {
      print("Error fetching route: $e");
    } finally {
      setState(() => isLoading = false);
    }
  }

  void _generatePassengers() {
    const double groupRadius = 50.0;
    const double spawnRadius = 50.0;
    const int minPassengers = 3;
    const int maxPassengers = 8;

    List<PassengerMarker> newPassengers = [];
    int totalPassengers =
        _random.nextInt(maxPassengers - minPassengers + 1) + minPassengers;

    for (int i = 0; i < totalPassengers; i++) {
      LatLng position = _getRandomPointNearRoute(spawnRadius);
      int distance = _calculateDistance(jeepneyPosition, position).round();

      bool addedToGroup = false;
      for (var group in newPassengers) {
        if (_calculateDistance(position, group.position) <= groupRadius) {
          group.groupSize++;
          addedToGroup = true;
          break;
        }
      }

      if (!addedToGroup) {
        newPassengers.add(
          PassengerMarker(position: position, distance: distance, groupSize: 1),
        );
      }
    }

    setState(() => passengers = newPassengers);
  }

  LatLng _getRandomPointNearRoute(double maxDistance) {
    if (routePoints.isEmpty) return jeepneyPosition;

    double metersToDegrees = maxDistance / 111320.0;
    double randomDistance = _random.nextDouble() * metersToDegrees;
    double randomAngle = _random.nextDouble() * 2 * pi;

    int segmentIndex = _random.nextInt(routePoints.length - 1);
    double segmentProgress = _random.nextDouble();
    LatLng routePoint = LatLng(
      routePoints[segmentIndex].latitude +
          (routePoints[segmentIndex + 1].latitude -
                  routePoints[segmentIndex].latitude) *
              segmentProgress,
      routePoints[segmentIndex].longitude +
          (routePoints[segmentIndex + 1].longitude -
                  routePoints[segmentIndex].longitude) *
              segmentProgress,
    );

    return LatLng(
      routePoint.latitude + randomDistance * cos(randomAngle),
      routePoint.longitude + randomDistance * sin(randomAngle),
    );
  }

  void _confirmRoute() {
    setState(() {
      routeConfirmed = true;
      _generatePassengers();
    });
  }

  double _calculateDistance(LatLng p1, LatLng p2) {
    return Geolocator.distanceBetween(
      p1.latitude,
      p1.longitude,
      p2.latitude,
      p2.longitude,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Listener(
            onPointerDown: (event) {
              if (event.buttons == kPrimaryMouseButton && !routeConfirmed) {
                setState(() => _isDraggingJeepney = true);
              }
            },
            onPointerMove: (event) {
              if (_isDraggingJeepney && !routeConfirmed) {
                setState(() => _dragPosition = event.localPosition);
              }
            },
            onPointerUp: (_) async {
              if (_dragPosition != null &&
                  _isDraggingJeepney &&
                  !routeConfirmed) {
                final latLng = pointToLatLng(_dragPosition!);
                setState(() {
                  jeepneyPosition = latLng;
                  _isDraggingJeepney = false;
                  _dragPosition = null;
                });
                final name = await _getLocationName(latLng);
                setState(() => destinationName = name);
              }
            },
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: jeepneyPosition,
                initialZoom: 16.0,
                onTap: _handleMapTap,
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
                  userAgentPackageName: 'com.example.para2',
                ),
                if (routePoints.isNotEmpty)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: routePoints,
                        color: Colors.blue,
                        strokeWidth: 4,
                      ),
                    ],
                  ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: jeepneyPosition,
                      width: 40,
                      height: 40,
                      child: Image.asset(
                        'assets/JEEP LOGO.png',
                        width: 40,
                        height: 95,
                      ),
                    ),
                    if (destination != null)
                      Marker(
                        point: destination!,
                        width: 30,
                        height: 30,
                        child: const Icon(
                          Icons.location_on,
                          color: Colors.green,
                          size: 30,
                        ),
                      ),
                    ...passengers.map(
                      (p) => Marker(
                        point: p.position,
                        width: 30,
                        height: 30,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.7),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              '${p.groupSize}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Positioned(
            top: 40,
            left: 20,
            child: IconButton(
              icon: const Icon(Icons.menu, size: 30),
              onPressed: () {},
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.5,
              ),
              child: GestureDetector(
                onVerticalDragUpdate: (details) {
                  setState(() {
                    panelHeight = (panelHeight - details.primaryDelta!).clamp(
                      80.0,
                      maxPanelHeight,
                    );
                    isPanelUp = panelHeight > 100;
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: panelHeight,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 10,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Center(
                          child: Container(
                            width: 40,
                            height: 4,
                            margin: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.grey[400],
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            destination != null
                                ? 'Route: Manila → $destinationName'
                                : 'Tap map to set destination',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isPanelUp && passengers.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: passengers
                                  .map(
                                    (p) => Container(
                                      width: 100,
                                      height: 100,
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: Colors.green[400],
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              const Icon(
                                                Icons.person,
                                                color: Colors.white,
                                                size: 24,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                '${p.groupSize}',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            '${p.distance}m',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 16,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ),
                        if (destination != null && !routeConfirmed)
                          Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                minimumSize: const Size(double.infinity, 50),
                              ),
                              onPressed: _confirmRoute,
                              child: const Text(
                                'Set Route',
                                style: TextStyle(
                                  fontSize: 18,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        SizedBox(height: MediaQuery.of(context).padding.bottom),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (isLoading) const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }

  pointToLatLng(Offset offset) {}
}
