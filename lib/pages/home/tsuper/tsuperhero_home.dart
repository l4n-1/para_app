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

  // Manual passenger counter
  int _currentPassengers = 0;
  int _maxCapacity = 20;
  bool _isEditingCapacity = false;

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
      _plateNumber = data['plateNumber'] ?? 'DRVR-XXX';
      final boxId = data['boxClaimed'];

      if (boxId != null) {
        final boxDoc = await _firestore
            .collection('baryaBoxes')
            .doc(boxId)
            .get();
        if (boxDoc.exists) {
          _trackerId = boxDoc.data()?['trackerId'];
        }
      }

      // Load current passenger count from RTDB
      if (_trackerId != null) {
        await _loadCurrentPassengerCount();
        _listenToTracker(_trackerId!);
      }

      setState(() {});
    } catch (e) {
      debugPrint('Error initializing driver data: $e');
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
          setState(() {
            _currentPassengers = (data['currentPassengers'] as int?) ?? 0;
            _maxCapacity = (data['maxCapacity'] as int?) ?? 20;
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading passenger count: $e');
    }
  }

  void _listenToTracker(String trackerId) {
    _trackerSub?.cancel();

    final trackerRef = _rtdbService.getJeepneyGpsRef(trackerId);
    debugPrint("📡 Listening to tracker path: devices/$trackerId");

    _trackerSub = trackerRef.onValue.listen((event) async {
      final snapshot = event.snapshot;
      if (!snapshot.exists || snapshot.value == null) return;

      final raw = snapshot.value;
      if (raw is! Map) return;

      final data = raw.cast<String, dynamic>();
      final lat = double.tryParse(
        data['latitude']?.toString() ?? data['lat']?.toString() ?? '',
      );
      final lng = double.tryParse(
        data['longitude']?.toString() ?? data['lng']?.toString() ?? '',
      );
      final speed = double.tryParse(
        data['speed_kmh']?.toString() ?? data['speed']?.toString() ?? '0',
      );

      if (lat == null || lng == null) {
        debugPrint("⚠️ Invalid lat/lng for tracker $trackerId: $data");
        return;
      }

      final pos = LatLng(lat, lng);

      // Use medium icon by default (will be updated by SharedHome's zoom logic)
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

      debugPrint("📍 Jeep updated: ($lat, $lng) - Online: $_isOnline - Passengers: $_currentPassengers/$_maxCapacity");
    });
  }

  // Manual passenger counter methods
  void _incrementPassengers() {
    if (_currentPassengers < _maxCapacity) {
      setState(() {
        _currentPassengers++;
      });
      _updatePassengerCountInRTDB();
    }
  }

  void _decrementPassengers() {
    if (_currentPassengers > 0) {
      setState(() {
        _currentPassengers--;
      });
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
      debugPrint("✅ Updated passenger count: $_currentPassengers/$_maxCapacity");
    } catch (e) {
      debugPrint('❌ Error updating passenger count: $e');
    }
  }

  void _showCapacityEditor() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Set Maximum Capacity'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Current: $_maxCapacity passengers'),
            const SizedBox(height: 16),
            Slider(
              value: _maxCapacity.toDouble(),
              min: 10,
              max: 30,
              divisions: 20,
              label: _maxCapacity.toString(),
              onChanged: (value) {
                setState(() {
                  _maxCapacity = value.toInt();
                });
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              _updatePassengerCountInRTDB();
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Widget _buildEarningsSection() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green[100]!),
      ),
      child: Column(
        children: [
          const Row(
            children: [
              Icon(Icons.attach_money, color: Colors.green),
              SizedBox(width: 8),
              Text(
                'Today\'s Earnings',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Digital Rides:'),
              Text('₱0.00', style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Cash Rides:'),
              Text('₱0.00', style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          const Divider(),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total Earnings:'),
              Text('₱0.00',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: Colors.green
                  )),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '💡 Digital payments earn you 90% of the fare',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
              fontStyle: FontStyle.italic,
            ),
            textAlign: TextAlign.center,
          ),
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

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isOnline ? '🟢 You are now ONLINE - Visible to passengers' : '🔴 You are now OFFLINE',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      debugPrint('Error updating online status: $e');
    }
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
      roleContentBuilder: (context, role, userLoc, onMapTap) =>
          _buildDriverContent(),
    );
  }

  Widget _buildDriverContent() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Earnings Section
        _buildEarningsSection(),

        // Status and Passenger Counter
        Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              // Online Status
              Text(
                _isOnline ? "🟢 ONLINE - VISIBLE TO PASSENGERS" : "🔴 OFFLINE",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: _isOnline ? Colors.green : Colors.red,
                ),
              ),
              const SizedBox(height: 16),

              // Passenger Counter
              const Text(
                'Passenger Counter',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Decrement Button
                  IconButton(
                    onPressed: _decrementPassengers,
                    icon: const Icon(Icons.remove_circle_outline),
                    color: Colors.red,
                    iconSize: 32,
                  ),

                  // Passenger Count Display
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      color: _currentPassengers >= _maxCapacity
                          ? Colors.red.withOpacity(0.1)
                          : Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _currentPassengers >= _maxCapacity
                            ? Colors.red
                            : Colors.green,
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(
                          '$_currentPassengers',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '/$_maxCapacity',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Increment Button
                  IconButton(
                    onPressed: _incrementPassengers,
                    icon: const Icon(Icons.add_circle_outline),
                    color: Colors.green,
                    iconSize: 32,
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // Capacity Warning
              if (_currentPassengers >= _maxCapacity)
                Text(
                  '⚠️ Capacity reached!',
                  style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),

              // Capacity Editor
              TextButton(
                onPressed: _showCapacityEditor,
                child: const Text('Adjust Maximum Capacity'),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Control Buttons
        Column(
          children: [
            ElevatedButton.icon(
              onPressed: _toggleOnlineStatus,
              style: ElevatedButton.styleFrom(
                elevation: 7,
                backgroundColor: _isOnline
                    ? Colors.red
                    : const Color.fromARGB(255, 35, 34, 37),
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
              ),
              icon: Icon(
                _isOnline ? Icons.power_settings_new : Icons.play_arrow,
                color: Colors.white,
              ),
              label: Text(
                _isOnline ? 'Go Offline' : 'Go Online',
                style: const TextStyle(color: Colors.white, fontSize: 15),
              ),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: () async {
                final sharedHome = SharedHome.of(context);
                if (sharedHome != null) {
                  await sharedHome.centerOnJeepMarker();
                } else {
                  debugPrint("SharedHome not found in context");
                }
              },
              child: const Text("Center Map on My Jeep"),
            ),
          ],
        ),

        // BaryaBox Status
        const SizedBox(height: 20),
        _trackerId != null
            ? Text(
          '📍 Tracking via BaryaBox: $_trackerId',
          style: const TextStyle(
            fontSize: 12,
            color: Colors.green,
            fontWeight: FontWeight.w500,
          ),
          textAlign: TextAlign.center,
        )
            : const Text(
          '❌ No BaryaBox connected',
          style: TextStyle(
            fontSize: 12,
            color: Colors.red,
            fontWeight: FontWeight.w500,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  List<Widget> _buildDriverMenu() {
    return [
      // ADD TO BOTH FILES IN _buildPasaheroMenu() AND _buildDriverMenu()
      ListTile(
        leading: const Icon(Icons.history),
        title: const Text('Biyahe Logs'),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => BiyaheLogsPage(userType: 'tsuperhero'),
            ),
          );
        },
      ),
      ListTile(
        leading: const Icon(Icons.qr_code_scanner),
        title: const Text('Scan Activation QR'),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const QRScanPage()),
          );
        },
      ),
      ListTile(
        leading: const Icon(Icons.people),
        title: const Text('Passenger Management'),
        subtitle: Text('Current: $_currentPassengers/$_maxCapacity'),
        onTap: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Use the passenger counter on main screen')),
          );
        },
      ),
      ListTile(
        leading: const Icon(Icons.route),
        title: const Text('Assigned Route'),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ProfileSettingsPage()),
          );
        },
      ),
      ListTile(
        leading: const Icon(Icons.person),
        title: const Text('Profile Settings'),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ProfileSettingsPage()),
          );
        },
      ),
      ListTile(
        leading: const Icon(Icons.settings),
        title: const Text('Driver Settings'),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ProfileSettingsPage()),
          );
        },
      ),
    ];
  }

  Future<void> _handleSignOut() async {
    await _auth.signOut();
    await _trackerSub?.cancel();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
    );
  }

  // Add this method to your existing TsuperheroHome class
  Future<void> _loadUserDisplayName() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final doc = await _firestore.collection('users').doc(user.uid).get();
      if (doc.exists) {
        final data = doc.data()!;

        // ✅ FIXED: Format as "FirstName L." (Last Name Initial)
        String formattedName = 'Driver';

        final firstName = data['firstName']?.toString() ?? '';
        final lastName = data['lastName']?.toString() ?? '';

        if (firstName.isNotEmpty && lastName.isNotEmpty) {
          formattedName = '$firstName ${lastName[0]}.';
        } else if (firstName.isNotEmpty) {
          formattedName = firstName;
        } else if (user.displayName != null) {
          final nameParts = user.displayName!.split(' ');
          if (nameParts.length >= 2) {
            formattedName = '${nameParts[0]} ${nameParts[1][0]}.';
          } else {
            formattedName = user.displayName!;
          }
        }

        // Update any display name variables in your state
        setState(() {
          // Update your display name variable here
        });
      }
    } catch (e) {
      debugPrint('Error loading user name: $e');
    }
  }
}