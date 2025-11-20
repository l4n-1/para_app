import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

class LocationService {
  static Future<LatLng?> getCurrentLocation() async {
    try {
      // Check permissions
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return null;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        return null;
      }

      // Get current position
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      return LatLng(position.latitude, position.longitude);
    } catch (e) {
      print('Location error: $e');
      return null;
    }
  }

  /// Try to return the last known location without prompting for permissions.
  /// Falls back to null if not available.
  static Future<LatLng?> getLastKnownLocation() async {
    try {
      final Position? pos = await Geolocator.getLastKnownPosition();
      if (pos == null) return null;
      return LatLng(pos.latitude, pos.longitude);
    } catch (e) {
      // ignore errors and return null
      return null;
    }
  }

  static Future<void> centerToLocation(GoogleMapController controller, LatLng location) async {
    try {
      await controller.animateCamera(
        CameraUpdate.newLatLngZoom(location, 16.0),
      );
    } catch (e) {
      print('Center error: $e');
    }
  }
}