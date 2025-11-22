For jeepney_routes.dart (NEW CREATE A NEW FOLDER NAMED data, under that folder is this new dart file)

import 'package:google_maps_flutter/google_maps_flutter.dart';

class JeepneyRoute {
  final String id;          // internal ID
  final String displayName; // shown to driver / passenger
  final List<LatLng> points; // ordered along the route (A -> B)

  const JeepneyRoute({
    required this.id,
    required this.displayName,
    required this.points,
  });
}

/// 👉 Define your jeepney routes here, one by one.
/// For now I’ll put fake coords – you will replace them
/// with real lat/lng taken from Google Maps.
const Map<String, JeepneyRoute> kJeepneyRoutes = {
  'route_1_marilao_malolos': JeepneyRoute(
    id: 'route_1_marilao_malolos',
    displayName: 'Marilao – Malolos',
    points: [
      // Example only. Replace with your real coordinates.
      LatLng(14.777800, 120.975000), // near Marilao bridge
      LatLng(14.783200, 120.979500),
      LatLng(14.789100, 120.984000),
      LatLng(14.796000, 120.989500), // entering Bocaue
      LatLng(14.807300, 120.996200),
      LatLng(14.818400, 121.002800), // Balagtas town center
      LatLng(14.828500, 121.008500),
      LatLng(14.838600, 121.014200), // nearing Guiguinto
      LatLng(14.848700, 121.021000),
      LatLng(14.859800, 121.028400), // Guiguinto town center
      LatLng(14.869900, 121.034800),
      LatLng(14.880000, 121.041500), // near Malolos boundary
      LatLng(14.890100, 121.048200), // Terminal B
    ],
  ),

  // Add more routes here:
  // 'route_2_xyz': JeepneyRoute(...),
};

---------