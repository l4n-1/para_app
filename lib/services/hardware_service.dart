class HardwareService {
  Future<Map<String, dynamic>> getMockGPSData() async {
    return {
      'lat': 14.5995,
      'lng': 120.9842,
      'timestamp': DateTime.now().toIso8601String(),
    };
  }
}
