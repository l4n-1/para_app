// lib/pages/settings/THsettings.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:para2/services/RealtimeDatabaseService.dart';

class THsettings extends StatefulWidget {
  const THsettings({super.key});

  @override
  State<THsettings> createState() => _THsettingsState();
}

class _THsettingsState extends State<THsettings> {
  final RealtimeDatabaseService _rtdbService = RealtimeDatabaseService();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _rideRequestsEnabled = true;
  bool _autoGoOnline = false;
  bool _showEarnings = true;
  bool _lowBatteryAlerts = true;
  bool _maintenanceReminders = true;

  String? _trackerId;
  int _maxCapacity = 20;
  String _plateNumber = '';

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadDriverData();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _rideRequestsEnabled = prefs.getBool('tsuperhero_requests') ?? true;
      _autoGoOnline = prefs.getBool('tsuperhero_auto_online') ?? false;
      _showEarnings = prefs.getBool('tsuperhero_show_earnings') ?? true;
      _lowBatteryAlerts = prefs.getBool('tsuperhero_battery_alerts') ?? true;
      _maintenanceReminders = prefs.getBool('tsuperhero_maintenance') ?? true;
    });
  }

  Future<void> _loadDriverData() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final doc = await _firestore.collection('users').doc(user.uid).get();
      if (doc.exists) {
        final data = doc.data()!;
        setState(() {
          _trackerId = data['boxClaimed'];
          _plateNumber = data['plateNumber'] ?? 'Not Set';
          _maxCapacity = (data['maxCapacity'] as int?) ?? 20;
        });
      }
    } catch (e) {
      debugPrint('Error loading driver data: $e');
    }
  }

  Future<void> _saveSetting(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  Future<void> _updateMaxCapacity(int newCapacity) async {
    if (_trackerId == null) return;

    try {
      // Update in Realtime Database
      final trackerRef = _rtdbService.getJeepneyGpsRef(_trackerId!);
      await trackerRef.update({
        'maxCapacity': newCapacity,
        'hasAvailableSeats': true, // Reset when capacity changes
      });

      // Update in Firestore
      final user = _auth.currentUser;
      if (user != null) {
        await _firestore.collection('users').doc(user.uid).set({
          'maxCapacity': newCapacity,
        }, SetOptions(merge: true));
      }

      setState(() {
        _maxCapacity = newCapacity;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Maximum capacity updated')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Failed to update capacity: $e')),
      );
    }
  }

  void _showComingSoon(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$feature - Coming Soon!')),
    );
  }

  void _showCapacityDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Set Maximum Capacity'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Adjust the maximum number of passengers:'),
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
            Text('Maximum Capacity: $_maxCapacity passengers'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              _updateMaxCapacity(_maxCapacity);
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        children: [
          // Driver Preferences
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text(
                    'Driver Preferences',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.directions_bus),
                  title: const Text('Ride Requests'),
                  subtitle: const Text('Receive PARA! requests from passengers'),
                  trailing: Switch(
                    value: _rideRequestsEnabled,
                    onChanged: (value) {
                      setState(() {
                        _rideRequestsEnabled = value;
                      });
                      _saveSetting('tsuperhero_requests', value);
                    },
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.power),
                  title: const Text('Auto Go Online'),
                  subtitle: const Text('Automatically go online when app opens'),
                  trailing: Switch(
                    value: _autoGoOnline,
                    onChanged: (value) {
                      setState(() {
                        _autoGoOnline = value;
                      });
                      _saveSetting('tsuperhero_auto_online', value);
                    },
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.attach_money),
                  title: const Text('Show Earnings'),
                  subtitle: const Text('Display earnings on dashboard'),
                  trailing: Switch(
                    value: _showEarnings,
                    onChanged: (value) {
                      setState(() {
                        _showEarnings = value;
                      });
                      _saveSetting('tsuperhero_show_earnings', value);
                    },
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Vehicle Settings
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text(
                    'Vehicle Settings',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.confirmation_number),
                  title: const Text('Plate Number'),
                  subtitle: Text(_plateNumber.isEmpty ? 'Not set' : _plateNumber),
                  onTap: () => _showComingSoon('Plate Number Update'),
                ),
                ListTile(
                  leading: const Icon(Icons.people),
                  title: const Text('Passenger Capacity'),
                  subtitle: Text('Max: $_maxCapacity passengers'),
                  onTap: _showCapacityDialog,
                ),
                ListTile(
                  leading: const Icon(Icons.time_to_leave),
                  title: const Text('Vehicle Information'),
                  subtitle: const Text('Update vehicle details'),
                  onTap: () => _showComingSoon('Vehicle Information'),
                ),
                ListTile(
                  leading: const Icon(Icons.route),
                  title: const Text('Route Management'),
                  subtitle: const Text('Set your regular routes'),
                  onTap: () => _showComingSoon('Route Management'),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Alerts & Notifications
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text(
                    'Alerts & Maintenance',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.battery_alert),
                  title: const Text('Low Battery Alerts'),
                  subtitle: const Text('Get notified when battery is low'),
                  trailing: Switch(
                    value: _lowBatteryAlerts,
                    onChanged: (value) {
                      setState(() {
                        _lowBatteryAlerts = value;
                      });
                      _saveSetting('tsuperhero_battery_alerts', value);
                    },
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.build),
                  title: const Text('Maintenance Reminders'),
                  subtitle: const Text('Regular vehicle maintenance alerts'),
                  trailing: Switch(
                    value: _maintenanceReminders,
                    onChanged: (value) {
                      setState(() {
                        _maintenanceReminders = value;
                      });
                      _saveSetting('tsuperhero_maintenance', value);
                    },
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Support & Resources
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text(
                    'Support & Resources',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.help),
                  title: const Text('Driver Support'),
                  onTap: () => _showComingSoon('Driver Support'),
                ),
                ListTile(
                  leading: const Icon(Icons.business_center),
                  title: const Text('Driver Resources'),
                  onTap: () => _showComingSoon('Driver Resources'),
                ),
                ListTile(
                  leading: const Icon(Icons.school),
                  title: const Text('Training Materials'),
                  onTap: () => _showComingSoon('Training Materials'),
                ),
                ListTile(
                  leading: const Icon(Icons.contact_support),
                  title: const Text('Contact Dispatch'),
                  onTap: () => _showComingSoon('Contact Dispatch'),
                ),
              ],
            ),
          ),

          // BaryaBox Info
          if (_trackerId != null) ...[
            const SizedBox(height: 16),
            Card(
              color: Colors.green[50],
              child: ListTile(
                leading: const Icon(Icons.qr_code, color: Colors.green),
                title: const Text('BaryaBox Connected'),
                subtitle: Text('Device ID: $_trackerId'),
                trailing: const Icon(Icons.check_circle, color: Colors.green),
              ),
            ),
          ],
        ],
      ),
    );
  }
}