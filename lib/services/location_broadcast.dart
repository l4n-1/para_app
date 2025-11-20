import 'dart:async';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// A simple broadcast service for location updates so multiple widgets
/// can subscribe without relying on widget ancestor lookups.
class LocationBroadcast {
  LocationBroadcast._internal();

  static final LocationBroadcast instance = LocationBroadcast._internal();

  final StreamController<LatLng> _ctrl = StreamController<LatLng>.broadcast();

  Stream<LatLng> get stream => _ctrl.stream;

  void emit(LatLng loc) {
    if (!_ctrl.isClosed) _ctrl.add(loc);
  }

  void dispose() {
    _ctrl.close();
  }
}
