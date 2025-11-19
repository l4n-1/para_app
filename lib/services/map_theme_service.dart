import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kMapDarkModePrefKey = 'map_dark_mode';

class MapThemeService {
  MapThemeService._private();
  static final MapThemeService instance = MapThemeService._private();

  /// Notifier the UI or other callers can listen to for current map theme.
  final ValueNotifier<bool> isDarkMode = ValueNotifier<bool>(false);

  /// A widely used dark style for Google Maps. You can replace this with
  /// a custom JSON style if you prefer.
  static const String _darkMapStyle = '''[
  {"elementType": "geometry", "stylers": [{"color": "#242f3e"}]},
  {"elementType": "labels.text.stroke", "stylers": [{"color": "#242f3e"}]},
  {"elementType": "labels.text.fill", "stylers": [{"color": "#746855"}]},
  {"featureType": "administrative.locality", "elementType": "labels.text.fill", "stylers": [{"color": "#d59563"}]},
  {"featureType": "poi", "elementType": "labels.text.fill", "stylers": [{"color": "#d59563"}]},
  {"featureType": "poi.park", "elementType": "geometry", "stylers": [{"color": "#263c3f"}]},
  {"featureType": "poi.park", "elementType": "labels.text.fill", "stylers": [{"color": "#6b9a76"}]},
  {"featureType": "road", "elementType": "geometry", "stylers": [{"color": "#38414e"}]},
  {"featureType": "road", "elementType": "geometry.stroke", "stylers": [{"color": "#212a37"}]},
  {"featureType": "road", "elementType": "labels.text.fill", "stylers": [{"color": "#9ca5b3"}]},
  {"featureType": "road.highway", "elementType": "geometry", "stylers": [{"color": "#746855"}]},
  {"featureType": "water", "elementType": "geometry", "stylers": [{"color": "#17263c"}]},
  {"featureType": "water", "elementType": "labels.text.fill", "stylers": [{"color": "#515c6d"}]},
  {"featureType": "water", "elementType": "labels.text.stroke", "stylers": [{"color": "#17263c"}]}
]''';

  /// Apply the current theme to the provided [controller]. If [controller]
  /// is null this is a no-op.
  Future<void> applyThemeTo(GoogleMapController? controller) async {
    if (controller == null) return;
    try {
      if (isDarkMode.value) {
        await controller.setMapStyle(_darkMapStyle);
      } else {
        // Passing null resets to default (light) style
        await controller.setMapStyle(null);
      }
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('Error applying map style: $e');
      }
    }
  }

  /// Initialize the service by reading persisted preference (if any).
  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getBool(_kMapDarkModePrefKey);
      if (saved != null) isDarkMode.value = saved;
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('Error loading map theme preference: $e');
      }
    }
  }

  /// Toggle dark mode and apply style to the optional controller
  Future<void> toggle(GoogleMapController? controller) async {
    isDarkMode.value = !isDarkMode.value;
    // persist
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kMapDarkModePrefKey, isDarkMode.value);
    } catch (e) {
      if (kDebugMode) print('Error saving map theme preference: $e');
    }
    await applyThemeTo(controller);
  }
}
