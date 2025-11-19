import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

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