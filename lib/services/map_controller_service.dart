import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'map_theme_service.dart';

class MapControllerService {
  MapControllerService._private();
  static final MapControllerService instance = MapControllerService._private();

  final ValueNotifier<GoogleMapController?> controller = ValueNotifier<GoogleMapController?>(null);

  /// Set the active controller. This will also apply the current map theme
  /// (dark/light) to the controller if available.
  Future<void> setController(GoogleMapController? c) async {
    controller.value = c;
    try {
      await MapThemeService.instance.applyThemeTo(c);
    } catch (_) {
      // ignore errors here
    }
  }

  GoogleMapController? get current => controller.value;
}
