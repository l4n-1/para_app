import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../services/button_actions.dart';

class MapControls extends StatelessWidget {
  final GoogleMapController? mapController;
  final LatLng? userLocation;
  final VoidCallback? onRecenterd;

  const MapControls({
    super.key,
    this.mapController,
    this.userLocation,
    this.onRecenterd,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 120,
      right: 16,
      child: Column(
        children: [
          // Recenter Button
          _MapControlButton(
            icon: Icons.my_location,
            tooltip: 'Center to my location',
            onPressed: () {
              ButtonActions.recenterToUser(context, mapController, userLocation);
              onRecenterd?.call();
            },
          ),
          const SizedBox(height: 8),

          // Map theme toggle
          _MapControlButton(
            icon: Icons.brightness_6,
            tooltip: 'Toggle map theme',
            onPressed: () => ButtonActions.toggleMapTheme(context, mapController),
          ),
          const SizedBox(height: 8),

          // Trophy Button
          _MapControlButton(
            icon: Icons.emoji_events,
            tooltip: 'Achievements',
            onPressed: () => ButtonActions.showTrophyDialog(context),
          ),
          const SizedBox(height: 8),

          // Compass Button
          _MapControlButton(
            icon: Icons.explore,
            tooltip: 'Compass mode',
            onPressed: ButtonActions.toggleCompassMode,
          ),
          const SizedBox(height: 8),

          // Route Button
          _MapControlButton(
            icon: Icons.route,
            tooltip: 'Plan route',
            onPressed: () => ButtonActions.showRoutePlanner(context),
          ),
        ],
      ),
    );
  }
}

class _MapControlButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _MapControlButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      mini: true,
      backgroundColor: Colors.white,
      onPressed: onPressed,
      child: Icon(icon, color: Colors.blue, size: 20),
    );
  }
}