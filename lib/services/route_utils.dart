// lib/services/route_utils.dart
// Utilities for matching routes and finding overlapping nodes.

import 'dart:math' as math;
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Finds the last overlapping node between two ordered lists of route nodes
/// (routeA and routeB). The function treats an element pair as "matching"
/// when their geographic distance is <= [toleranceMeters]. It finds the
/// longest contiguous overlapping sequence (longest common substring by
/// geographic proximity) and returns the last node of that overlap.
///
/// Returns `null` if there is no overlap.
///
/// Behavior for the three cases you mentioned:
/// - One route fully inside the other: the longest overlap will be the
///   entire shorter route; the returned node is the last node of that
///   overlap.
/// - Partial overlap: the longest contiguous overlap is used; the last
///   overlapping node is returned.
/// - No overlap: returns `null`.
///
/// Notes:
/// - This uses an O(n*m) dynamic programming approach which is fine for
///   route lists with a few hundred nodes. If you have thousands of nodes
///   you may want a more optimized approach (e.g., hashing into spatial bins).
LatLng? findLastOverlappingNode(
  List<LatLng> routeA,
  List<LatLng> routeB, {
  double toleranceMeters = 20.0,
}) {
  if (routeA.isEmpty || routeB.isEmpty) return null;

  final int n = routeA.length;
  final int m = routeB.length;

  // dp[i][j] = length of longest common suffix of routeA[0..i-1] and routeB[0..j-1]
  final dp = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));

  int maxLen = 0;
  int endAi = 0;
  int endBj = 0;

  for (int i = 1; i <= n; i++) {
    for (int j = 1; j <= m; j++) {
      if (_distanceMeters(routeA[i - 1], routeB[j - 1]) <= toleranceMeters) {
        dp[i][j] = dp[i - 1][j - 1] + 1;
        if (dp[i][j] > maxLen) {
          maxLen = dp[i][j];
          endAi = i - 1; // last index in routeA of the match
          endBj = j - 1; // last index in routeB of the match
        }
      } else {
        dp[i][j] = 0;
      }
    }
  }

  if (maxLen == 0) return null;

  // We return the averaged point between the two matched endpoints so both
  // roles get a stable mutual coordinate (they are within tolerance).
  final LatLng a = routeA[endAi];
  final LatLng b = routeB[endBj];
  return LatLng((a.latitude + b.latitude) / 2.0, (a.longitude + b.longitude) / 2.0);
}

/// Haversine distance (meters) between two LatLng points.
double _distanceMeters(LatLng a, LatLng b) {
  const R = 6371000.0; // Earth radius in meters
  final lat1 = _degToRad(a.latitude);
  final lat2 = _degToRad(b.latitude);
  final dLat = _degToRad(b.latitude - a.latitude);
  final dLon = _degToRad(b.longitude - a.longitude);

  final sinDLat = math.sin(dLat / 2);
  final sinDLon = math.sin(dLon / 2);
  final h = sinDLat * sinDLat + math.cos(lat1) * math.cos(lat2) * sinDLon * sinDLon;
  final c = 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
  return R * c;
}

double _degToRad(double deg) => deg * math.pi / 180.0;
