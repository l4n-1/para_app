import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'map_theme_service.dart';
import 'map_controller_service.dart';

class ButtonActions {
  // Recenter button action
  static Future<void> recenterToUser(
      BuildContext context,
      GoogleMapController? controller,
      LatLng? userLocation,
      ) async {
    if (controller == null || userLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location not available')),
      );
      return;
    }

    try {
      await controller.animateCamera(
        CameraUpdate.newLatLngZoom(userLocation, 16.0),
      );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('📍 Centered to your location'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  // Trophy button action
  static void showTrophyDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('🏆 Achievements'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Your achievements will appear here!'),
            SizedBox(height: 16),
            ListTile(
              leading: Icon(Icons.emoji_events, color: Colors.amber),
              title: Text('First Ride'),
              subtitle: Text('Complete your first jeepney ride'),
            ),
            ListTile(
              leading: Icon(Icons.people, color: Colors.blue),
              title: Text('Regular Commuter'),
              subtitle: Text('Take 10 rides'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  // Compass button action
  static void toggleCompassMode() {
    // Add compass functionality here
    print('Compass mode toggled');
  }

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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(enabled ? 'Map: Dark mode' : 'Map: Light mode'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  // Route planning button
  static void showRoutePlanner(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('🚍 Plan Route'),
        content: const Text('Route planning feature coming soon!'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}