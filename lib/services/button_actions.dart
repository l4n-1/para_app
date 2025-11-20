import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'map_theme_service.dart';
import 'map_controller_service.dart';
import 'follow_service.dart';
import 'package:para2/services/location_service.dart';
import 'package:para2/services/snackbar_service.dart';

class ButtonActions {
  // Recenter button action
  static Future<void> recenterToUser(
      BuildContext context,
      GoogleMapController? controller,
      LatLng? userLocation,
      ) async {
    // If no controller passed, try the global controller
    controller ??= MapControllerService.instance.current;
    if (controller == null || userLocation == null) {
      SnackbarService.show(context, 'Location not available');
      return;
    }

    try {
      await controller.animateCamera(
        CameraUpdate.newLatLngZoom(userLocation, 16.0),
      );

      SnackbarService.show(context, 'Centered to your location', duration: const Duration(seconds: 2));
    } catch (e) {
      SnackbarService.show(context, 'Error: $e');
    }
  }

  // Trophy button action
  // (Achievements UI removed — feature replaced by other UX)

  // (Compass functionality removed)

  /// Toggle the Google Map theme between light and dark. If a controller is
  /// provided the style will be applied immediately.
  static Future<void> toggleMapTheme(
    BuildContext context,
    GoogleMapController? controller,
  ) async {
    // If caller didn't provide a controller, try the global one
    final ctrl = controller ?? MapControllerService.instance.current;
    await MapThemeService.instance.toggle(ctrl);
    final enabled = MapThemeService.instance.isDarkMode.value;
    SnackbarService.show(context, enabled ? 'Map: Dark mode' : 'Map: Light mode', duration: const Duration(seconds: 1));
  }

  /// Toggle follow-on-move mode. When enabled the map will follow the user's
  /// live location updates; when disabled the camera is free-roam.
  static Future<void> toggleFollowMode(BuildContext context) async {
    final enabled = FollowService.instance.toggle();
    SnackbarService.show(context, enabled ? 'Following enabled' : 'Following disabled', duration: const Duration(seconds: 1));

    // If follow mode was just enabled, immediately center the map to the
    // current (or last-known) user location so the user sees that follow is active.
    if (enabled) {
      try {
        final ctrl = MapControllerService.instance.current;
        if (ctrl == null) return;

        // Prefer a fresh current location; fall back to last-known location.
        LatLng? loc = await LocationService.getCurrentLocation();
        loc ??= await LocationService.getLastKnownLocation();

        if (loc != null) {
          await ctrl.animateCamera(
            CameraUpdate.newLatLngZoom(loc, 16.0),
          );
        }
      } catch (e) {
        debugPrint('Error recentering when enabling follow: $e');
      }
    }
  }

  // (Route planner removed)
}