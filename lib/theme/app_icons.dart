import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter/material.dart';

class AppIcons {
  static BitmapDescriptor? jeepIcon;
  static BitmapDescriptor? userPin;


  static Future<void> loadIcons() async {
    jeepIcon = await BitmapDescriptor.asset(
      const ImageConfiguration(),
      'assets/JEEP_LOGO(real).png', 
    );
    userPin = await BitmapDescriptor.asset(
      const ImageConfiguration(),
      'assets/USERPIN.png',
    );
  }

  static BitmapDescriptor getJeepIconForZoom(double zoom) => jeepIcon ?? BitmapDescriptor.defaultMarker;
  static BitmapDescriptor? get jeepIconSmall => jeepIcon;
  static BitmapDescriptor? get jeepIconMedium => jeepIcon;
  static BitmapDescriptor? get jeepIconLarge => jeepIcon;
}