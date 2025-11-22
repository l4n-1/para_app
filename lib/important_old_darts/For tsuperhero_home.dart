For tsuperhero_home.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:para2/pages/login/login.dart';
import 'package:para2/pages/home/shared_home.dart';
import 'package:para2/pages/login/qr_scan_page.dart';
import 'package:para2/services/RealtimeDatabaseService.dart';
import 'package:para2/theme/app_icons.dart';
import 'package:para2/pages/settings/profile_settings.dart';
import 'package:para2/pages/biyahe/biyahe_logs_page.dart';
import 'package:para2/services/snackbar_service.dart';

class TsuperheroHome extends StatefulWidget {
  const TsuperheroHome({super.key});

  @override
  State<TsuperheroHome> createState() => _TsuperheroHomeState();
}

class _TsuperheroHomeState extends State<TsuperheroHome> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final RealtimeDatabaseService _rtdbService = RealtimeDatabaseService();

  StreamSubscription? _trackerSub;
  Marker? _jeepMarker;
  bool _hasCentered = false;

  String _plateNumber = 'DRVR-XXX';
  bool _isOnline = false;
  String? _trackerId;

  int _currentPassengers = 0;
  int _maxCapacity = 20;

  @override
  void initState() {
    super.initState();
    _initDriverData();
  }

  Future<void> _initDriverData() async {
    final user = _auth.currentUser;
    if (user == null) return;
    try {
      final doc = await _firestore.collection('users').doc(user.uid).get();
      if (!doc.exists) return;
      final data = doc.data() ?? {};
      _plateNumber = data['plateNumber'] ?? _plateNumber;
      final boxId = data['boxClaimed'] ?? data['deviceId'];
      if (boxId != null) {
        final boxDoc = await _firestore.collection('baryaBoxes').doc(boxId).get();
        if (boxDoc.exists) {
          _trackerId = boxDoc.data()?['trackerId']?.toString() ?? boxId.toString();
        }
      }
      if (_trackerId != null) {
        await _loadCurrentPassengerCount();
        _listenToTracker(_trackerId!);
      }
      setState(() {});
    } catch (e) {
      debugPrint('Error init driver data: $e');
    }
  }

  Future<void> _loadCurrentPassengerCount() async {
    if (_trackerId == null) return;
    try {
      final trackerRef = _rtdbService.getJeepneyGpsRef(_trackerId!);
      final snapshot = await trackerRef.get();
      if (snapshot.exists) {
        final data = snapshot.value as Map<dynamic, dynamic>?;
        if (data != null) {
          _currentPassengers = (data['currentPassengers'] as int?) ?? 0;
          _maxCapacity = (data['maxCapacity'] as int?) ?? 20;
        }
      }
    } catch (e) {
      debugPrint('Error load passenger count: $e');
    }
  }

  void _listenToTracker(String trackerId) {
    _trackerSub?.cancel();
    final trackerRef = _rtdbService.getJeepneyGpsRef(trackerId);
    debugPrint("Listening to tracker: devices/$trackerId");
    _trackerSub = trackerRef.onValue.listen((event) async {
      final snapshot = event.snapshot;
      if (!snapshot.exists || snapshot.value == null) return;
      final raw = snapshot.value;
      if (raw is! Map) return;
      final data = raw.cast<String, dynamic>();
      final lat = double.tryParse(data['latitude']?.toString() ?? data['lat']?.toString() ?? '');
      final lng = double.tryParse(data['longitude']?.toString() ?? data['lng']?.toString() ?? '');
      final speed = double.tryParse(data['speed_kmh']?.toString() ?? data['speed']?.toString() ?? '0');
      if (lat == null || lng == null) return;
      final pos = LatLng(lat, lng);

      final marker = Marker(
        markerId: const MarkerId('tsuperhero_jeep'),
        position: pos,
        icon: _isOnline
            ? (AppIcons.jeepIconMedium ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen))
            : BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
        infoWindow: InfoWindow(
          title: _isOnline ? '$_plateNumber (Online)' : '$_plateNumber (Offline)',
          snippet: 'Speed: ${(speed ?? 0).toStringAsFixed(1)} km/h | Passengers: $_currentPassengers/$_maxCapacity',
        ),
        rotation: double.tryParse(data['course']?.toString() ?? '0') ?? 0,
        anchor: const Offset(0.5, 0.5),
        flat: true,
      );

      setState(() => _jeepMarker = marker);

      final sharedHome = SharedHome.of(context);
      if (sharedHome != null) {
        sharedHome.addOrUpdateMarker(const MarkerId('tsuperhero_jeep'), marker);
        if (!_hasCentered) {
          await sharedHome.centerMap(pos);
          _hasCentered = true;
        }
      }
    }, onError: (e) => debugPrint('Tracker listen error: $e'));
  }

  void _incrementPassengers() {
    if (_currentPassengers < _maxCapacity) {
      setState(() => _currentPassengers++);
      _updatePassengerCountInRTDB();
    }
  }

  void _decrementPassengers() {
    if (_currentPassengers > 0) {
      setState(() => _currentPassengers--);
      _updatePassengerCountInRTDB();
    }
  }

  Future<void> _updatePassengerCountInRTDB() async {
    if (_trackerId == null) return;
    try {
      final trackerRef = _rtdbService.getJeepneyGpsRef(_trackerId!);
      await trackerRef.update({
        'currentPassengers': _currentPassengers,
        'maxCapacity': _maxCapacity,
        'hasAvailableSeats': _currentPassengers < _maxCapacity,
        'lastUpdate': ServerValue.timestamp,
      });
      debugPrint("Updated passenger count: $_currentPassengers/$_maxCapacity");
    } catch (e) {
      debugPrint('Error updating passenger count: $e');
    }
  }

  void _showCapacityEditor() {
    showDialog(
      context: context,
      builder: (context) {
        int temp = _maxCapacity;
        return AlertDialog(
          title: const Text('Set Maximum Capacity'),
          content: StatefulBuilder(builder: (context, setStateSB) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Current: $temp passengers'),
                Slider(
                  value: temp.toDouble(),
                  min: 8,
                  max: 30,
                  divisions: 22,
                  label: temp.toString(),
                  onChanged: (v) => setStateSB(() => temp = v.toInt()),
                ),
              ],
            );
          }),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                setState(() => _maxCapacity = temp);
                _updatePassengerCountInRTDB();
                Navigator.pop(context);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  Widget _driverHeader() {
    final displayName = _auth.currentUser?.displayName ?? 'Driver';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF11121A),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: Colors.grey.shade300,
            child: Icon(Icons.person, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(displayName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 2),
                Text('TSUPERHERO • Plate: $_plateNumber', style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 12)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              GestureDetector(
                onTap: _toggleOnlineStatus,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: _isOnline ? Colors.green : Colors.red,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(_isOnline ? Icons.wifi_tethering : Icons.wifi_off, color: Colors.white, size: 18),
                      const SizedBox(width: 6),
                      Text(_isOnline ? 'ONLINE' : 'OFFLINE', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(_trackerId != null ? 'Box: ${_trackerId!}' : 'No BaryaBox', style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 11)),
            ],
          )
        ],
      ),
    );
  }

  Widget _earningsCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 6)]),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.attach_money, color: Colors.green),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text("Today's Earnings", style: TextStyle(fontWeight: FontWeight.bold)),
                SizedBox(height: 6),
                Text("Digital: ₱0.00   •   Cash: ₱0.00", style: TextStyle(color: Colors.black87)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: const [
              Text("Total", style: TextStyle(fontSize: 12, color: Colors.grey)),
              SizedBox(height: 6),
              Text("₱0.00", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
            ],
          )
        ],
      ),
    );
  }

  Future<void> _toggleOnlineStatus() async {
    setState(() => _isOnline = !_isOnline);
    try {
      final user = _auth.currentUser;
      if (user != null) {
        await _firestore.collection('users').doc(user.uid).update({
          'isOnline': _isOnline,
          'lastStatusChange': FieldValue.serverTimestamp(),
        });
        if (_trackerId != null) {
          final trackerRef = _rtdbService.getJeepneyGpsRef(_trackerId!);
          await trackerRef.update({
            'isOnline': _isOnline,
            'currentPassengers': _currentPassengers,
            'maxCapacity': _maxCapacity,
            'hasAvailableSeats': _currentPassengers < _maxCapacity,
            'lastUpdate': ServerValue.timestamp,
          });
        }
      }
      SnackbarService.show(context, _isOnline ? 'You are now ONLINE' : 'You are now OFFLINE', duration: const Duration(seconds: 2));
    } catch (e) {
      debugPrint('Error toggling online: $e');
    }
  }

  Widget _passengerCounterCard() {
    final full = _currentPassengers >= _maxCapacity;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 6)]),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.group, color: Colors.black87),
              const SizedBox(width: 8),
              const Expanded(child: Text('Passenger Counter', style: TextStyle(fontWeight: FontWeight.bold))),
              InkWell(onTap: _showCapacityEditor, child: const Padding(padding: EdgeInsets.all(6), child: Text('Adjust Capacity', style: TextStyle(color: Colors.blue)))),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: _decrementPassengers,
                child: Container(
                  decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.red.shade50),
                  padding: const EdgeInsets.all(8),
                  child: const Icon(Icons.remove_circle_outline, color: Colors.red, size: 34),
                ),
              ),
              const SizedBox(width: 20),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 10),
                decoration: BoxDecoration(
                  color: full ? Colors.red.withOpacity(0.08) : Colors.green.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: full ? Colors.red : Colors.green),
                ),
                child: Column(
                  children: [
                    Text('$_currentPassengers', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                    Text('/ $_maxCapacity', style: const TextStyle(color: Colors.grey)),
                  ],
                ),
              ),
              const SizedBox(width: 20),
              GestureDetector(
                onTap: _incrementPassengers,
                child: Container(
                  decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.green.shade50),
                  padding: const EdgeInsets.all(8),
                  child: const Icon(Icons.add_circle_outline, color: Colors.green, size: 34),
                ),
              ),
            ],
          ),
          if (full) ...[
            const SizedBox(height: 10),
            Text('⚠️ Capacity reached', style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.bold)),
          ],
        ],
      ),
    );
  }

  Widget _buildDriverContent() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 12),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: _driverHeader()),
        const SizedBox(height: 12),
        _earningsCard(),
        const SizedBox(height: 12),
        _passengerCounterCard(),
        const SizedBox(height: 14),
      ],
    );
  }

  List<Widget> _buildDriverMenu() {
    return [
      ListTile(
        leading: const Icon(Icons.history),
        title: const Text('Biyahe Logs'),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => BiyaheLogsPage(userType: 'tsuperhero'))),
      ),
      ListTile(
        leading: const Icon(Icons.qr_code_scanner),
        title: const Text('Scan Activation QR'),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const QRScanPage())),
      ),
      ListTile(
        leading: const Icon(Icons.people),
        title: const Text('Passenger Management'),
        subtitle: Text('Current: $_currentPassengers/$_maxCapacity'),
        onTap: () => SnackbarService.show(context, 'Use the passenger counter on main screen'),
      ),
      ListTile(
        leading: const Icon(Icons.route),
        title: const Text('Assigned Route'),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileSettingsPage())),
      ),
      ListTile(
        leading: const Icon(Icons.person),
        title: const Text('Profile Settings'),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileSettingsPage())),
      ),
      ListTile(
        leading: const Icon(Icons.settings),
        title: const Text('Driver Settings'),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileSettingsPage())),
      ),
    ];
  }

  Future<void> _handleSignOut() async {
    await _auth.signOut();
    await _trackerSub?.cancel();
    if (!mounted) return;
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginPage()));
  }

  @override
  void dispose() {
    _trackerSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SharedHome(
      roleLabel: 'TSUPERHERO',
      onSignOut: _handleSignOut,
      roleMenu: _buildDriverMenu(),
      roleContentBuilder: (context, displayName, userLoc) => _buildDriverContent(),
    );
  }
}
