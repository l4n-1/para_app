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
import 'dart:math' as math;
import 'package:para2/services/ui_utils.dart';
import 'package:para2/services/button_actions.dart';
import 'package:para2/services/map_theme_service.dart';
import 'package:para2/theme/app_icons.dart';
import 'package:para2/pages/settings/profile_settings.dart';
import 'package:para2/pages/biyahe/biyahe_logs_page.dart';
import 'package:para2/services/snackbar_service.dart';
import 'package:para2/widgets/destination_display.dart';



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
  String _displayName = 'Driver';

  // Manual passenger counter
  int _currentPassengers = 0;
  int _maxCapacity = 20;
  bool _isEditingCapacity = false;
  // Driver actions state
  bool _showRouteMenu = false;
  String _selectedRoute = '';
  final List<String> _presetRoutes = [
    'Plaridel Crossing ↔ Malolos Crossing',
    'Downtown Loop',
    'Market District ↔ Station',
  ];

  @override
  void initState() {
    super.initState();
    _initDriverData();
    _loadUserDisplayName();
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

      SnackbarService.show(context, _isOnline ? '🟢 You are now ONLINE - Visible to passengers' : '🔴 You are now OFFLINE', duration: const Duration(seconds: 2));
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
      roleActions: _buildDriverActions(),
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

  List<Widget> _buildDriverMenu() => [
    Container(
    
      padding: const EdgeInsets.only(top: 10, bottom: 10),
      margin: EdgeInsets.only(right: 10,bottom: 8),
      decoration: BoxDecoration(
      color: const Color.fromARGB(255, 23, 22, 27),
      borderRadius: BorderRadius.only(topRight: Radius.circular(17),bottomRight: Radius.circular(17)),
      ),
      child: Column (
        
        children: [
    
          ListTile(
            visualDensity: const VisualDensity(vertical: -4),
              leading: const Icon(Icons.history),
              title: const Text('Biyahe Logs'),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => BiyaheLogsPage(userType: 'pasahero'), // or 'tsuperhero'
                  ),
                );
              },
            ),
            const Divider(
              color:  Color.fromARGB(255, 52, 46, 53),),
            ListTile(
              visualDensity: const VisualDensity(vertical: -4),
              leading: ValueListenableBuilder<bool>(
                valueListenable: MapThemeService.instance.isDarkMode,
                builder: (context, isDark, child) {
                  return Icon(isDark ? Icons.dark_mode : Icons.light_mode);
                },
              ),
              title: const Text('Display Theme'),
              onTap: () => ButtonActions.toggleMapTheme(context, null),
            ),
            const Divider(
              color:  Color.fromARGB(255, 52, 46, 53),),
            ListTile(
              visualDensity: const VisualDensity(vertical: -4),
              leading: const Icon(Icons.settings_sharp),
              title: const Text('Settings'),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ProfileSettingsPage()),
                );
              },
            ),
            const Divider(
              color:  Color.fromARGB(255, 52, 46, 53),),
            ListTile(
              visualDensity: const VisualDensity(vertical: -4),
              leading: const Icon(Icons.qr_code_2),
              title: const Text('Scan QR to Become Tsuperhero'),
              titleTextStyle: TextStyle(fontSize: 13),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const QRScanPage()),
                );
              },
            ),
              const Divider(
                color:  Color.fromARGB(255, 52, 46, 53),),



            const SizedBox(height: 70),




            ListTile(
              visualDensity: const VisualDensity(vertical: -4),
              leading: const Icon(Icons.feedback),
              title: const Text('Feedback'),
              titleTextStyle: TextStyle(fontSize: 13),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const QRScanPage()),
                );
              },
            ),
            
            ListTile(
              visualDensity: const VisualDensity(vertical: -4),
              leading: const Icon(Icons.handshake),
              title: const Text('Support Us'),
              titleTextStyle: TextStyle(fontSize: 13),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const QRScanPage()),
                );
              },
            ),

            ListTile(
              visualDensity: const VisualDensity(vertical: -4),
              leading: const Icon(Icons.book),
              title: const Text('Terms and Conditions'),
              titleTextStyle: TextStyle(fontSize: 13),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const QRScanPage()),
                );
              },
            ),
            ListTile(
              visualDensity: const VisualDensity(vertical: -4),
              leading: const Icon(Icons.help_center_rounded),
              title: const Text('About PARA!'),
              titleTextStyle: TextStyle(fontSize: 13),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const QRScanPage()),
                );
              },
            ),
        ],
      ),
    ),
  ];
      // ADD TO BOTH FILES IN _buildPasaheroMenu() AND _buildDriverMenu()

  List<Widget> _buildDriverActions() => [
    Column(
      children: [
        Row(
          children: [
            // Passenger suggestion area - horizontal, bounded height
            Expanded(
              child: SizedBox(
                height: 120,
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('para_requests')
                      .where('status', isEqualTo: 'pending')
                      .snapshots(),
                  builder: (context, snapshot) {
                    final cardWidth = UIUtils.responsiveCardWidth(context, fraction: 0.45, maxPx: 180.0);

                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final docs = snapshot.data!.docs;
                    // Filter requests that are reasonably close to driver (if we have tracker)
                    final nearby = <QueryDocumentSnapshot>[];
                    for (final d in docs) {
                      final data = d.data() as Map<String, dynamic>;
                      if (data['passengerLocation'] != null && _jeepMarker != null) {
                        final GeoPoint gp = data['passengerLocation'];
                        final dist = _distanceKm(LatLng(gp.latitude, gp.longitude), _jeepMarker!.position);
                        if (dist <= 5.0) {
                          nearby.add(d);
                          continue;
                        }
                      }
                      // fallback: include anyway
                      nearby.add(d);
                    }

                    if (nearby.isEmpty) {
                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(children: [
                          _buildPassengerPlaceholder(cardWidth),
                          _buildPassengerPlaceholder(cardWidth * 0.9),
                        ]),
                      );
                    }

                    return ListView(
                      scrollDirection: Axis.horizontal,
                      children: nearby.take(6).map((d) {
                        final data = d.data() as Map<String, dynamic>;
                        final id = d.id;
                        double? distKm;
                        if (data['passengerLocation'] != null && _jeepMarker != null) {
                          final gp = data['passengerLocation'] as GeoPoint;
                          distKm = _distanceKm(LatLng(gp.latitude, gp.longitude), _jeepMarker!.position);
                        }

                        return GestureDetector(
                          onTap: () {
                            // Driver taps passenger card - show info
                            SnackbarService.show(context, 'Selected request $id');
                          },
                          child: Container(
                            width: cardWidth,
                            margin: const EdgeInsets.only(right: 8, top: 6, bottom: 6),
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.06),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Req $id', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 6),
                                Text(data['passengerName'] ?? 'Passenger', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                                const SizedBox(height: 6),
                                Text(distKm != null ? '${distKm.toStringAsFixed(1)} km' : 'Calculating', style: const TextStyle(color: Colors.greenAccent, fontSize: 12)),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Fare / small action button placeholder
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: const [
                  Icon(Icons.attach_money, color: Colors.white),
                  SizedBox(height: 4),
                  Text('Fare', style: TextStyle(color: Colors.white)),
                ],
              ),
            ),
          ],
        ),

        const SizedBox(height: 8),

        // Seat management meter
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Seats', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              // Large, easy-to-tap +/- buttons for adjusting passenger count
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Decrement button
                    ElevatedButton(
                      onPressed: _decrementPassengers,
                      style: ElevatedButton.styleFrom(
                        shape: const CircleBorder(),
                        minimumSize: const Size(64, 64),
                        padding: const EdgeInsets.all(0),
                        backgroundColor: Colors.redAccent,
                        elevation: 6,
                      ),
                      child: const Icon(Icons.remove, size: 36, color: Colors.white),
                    ),

                    const SizedBox(width: 20),

                    // Passenger count display
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          Text('$_currentPassengers', style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text('/ $_maxCapacity', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                        ],
                      ),
                    ),

                    const SizedBox(width: 20),

                    // Increment button
                    ElevatedButton(
                      onPressed: _incrementPassengers,
                      style: ElevatedButton.styleFrom(
                        shape: const CircleBorder(),
                        minimumSize: const Size(64, 64),
                        padding: const EdgeInsets.all(0),
                        backgroundColor: Colors.green,
                        elevation: 6,
                      ),
                      child: const Icon(Icons.add, size: 36, color: Colors.white),
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('$_currentPassengers / $_maxCapacity', style: const TextStyle(color: Colors.white)),
                  TextButton(onPressed: _showCapacityEditor, child: const Text('Edit')),
                ],
              ),
            ],
          ),
        ),

        // Destination / Route selector (wrapped with dropdown)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            children: [
              GestureDetector(
                onTap: () {
                  setState(() {
                    _showRouteMenu = !_showRouteMenu;
                  });
                },
                child: Column(
                  children: [
                    DestinationDisplay(roleLabel: 'TSUPERHERO'),
                    if (_selectedRoute.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6.0),
                        child: Text('Selected: $_selectedRoute', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                      ),
                  ],
                ),
              ),
              if (_showRouteMenu)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: _presetRoutes.map((r) {
                      return ListTile(
                        dense: true,
                        title: Text(r, style: const TextStyle(color: Colors.white)),
                        onTap: () {
                          setState(() {
                            _selectedRoute = r;
                            _showRouteMenu = false;
                          });
                          SnackbarService.show(context, 'Selected route: $r');
                        },
                      );
                    }).toList(),
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  ];

  // Helper: build a placeholder passenger card
  Widget _buildPassengerPlaceholder(double width) {
    return Container(
      width: width,
      margin: const EdgeInsets.only(right: 8, top: 6, bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          SizedBox(height: 8),
          Text('Passenger', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          SizedBox(height: 6),
          Text('Waiting', style: TextStyle(color: Colors.white70, fontSize: 12)),
          SizedBox(height: 6),
          Text('– km', style: TextStyle(color: Colors.greenAccent, fontSize: 12)),
        ],
      ),
    );
  }

  double _degToRad(double deg) => deg * math.pi / 180;
  double _distanceKm(LatLng a, LatLng b) {
    const R = 6371;
    final dLat = _degToRad(b.latitude - a.latitude);
    final dLon = _degToRad(b.longitude - a.longitude);
    final aVal = math.sin(dLat / 2) * math.sin(dLat / 2) + math.cos(_degToRad(a.latitude)) * math.cos(_degToRad(b.latitude)) * math.sin(dLon / 2) * math.sin(dLon / 2);
    return R * 2 * math.atan2(math.sqrt(aVal), math.sqrt(1 - aVal));
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

        // Update display name in state
        setState(() {
          _displayName = formattedName;
        });
      }
    } catch (e) {
      debugPrint('Error loading user name: $e');
    }
  }
}