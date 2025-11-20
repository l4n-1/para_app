// lib/pages/settings/PHsettings.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:para2/services/snackbar_service.dart';

class PHsettings extends StatefulWidget {
  const PHsettings({super.key});

  @override
  State<PHsettings> createState() => _PHsettingsState();
}

class _PHsettingsState extends State<PHsettings> {
  bool _notificationsEnabled = true;
  bool _locationSharing = true;
  bool _rideUpdates = true;
  bool _promotionalEmails = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _notificationsEnabled = prefs.getBool('pasahero_notifications') ?? true;
      _locationSharing = prefs.getBool('pasahero_location') ?? true;
      _rideUpdates = prefs.getBool('pasahero_ride_updates') ?? true;
      _promotionalEmails = prefs.getBool('pasahero_promotions') ?? false;
    });
  }

  Future<void> _saveSetting(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  void _showComingSoon(String feature) {
    SnackbarService.show(context, '$feature - Coming Soon!');
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        children: [
          // Notifications Section
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text(
                    'Notifications',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.notifications_active),
                  title: const Text('Push Notifications'),
                  subtitle: const Text('Ride updates and alerts'),
                  trailing: Switch(
                    value: _notificationsEnabled,
                    onChanged: (value) {
                      setState(() {
                        _notificationsEnabled = value;
                      });
                      _saveSetting('pasahero_notifications', value);
                    },
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.directions_bus),
                  title: const Text('Ride Updates'),
                  subtitle: const Text('Real-time jeepney tracking'),
                  trailing: Switch(
                    value: _rideUpdates,
                    onChanged: (value) {
                      setState(() {
                        _rideUpdates = value;
                      });
                      _saveSetting('pasahero_ride_updates', value);
                    },
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.email),
                  title: const Text('Promotional Emails'),
                  subtitle: const Text('Discounts and special offers'),
                  trailing: Switch(
                    value: _promotionalEmails,
                    onChanged: (value) {
                      setState(() {
                        _promotionalEmails = value;
                      });
                      _saveSetting('pasahero_promotions', value);
                    },
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Privacy & Location
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text(
                    'Privacy & Location',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.location_on),
                  title: const Text('Location Sharing'),
                  subtitle: const Text('Share location with drivers during rides'),
                  trailing: Switch(
                    value: _locationSharing,
                    onChanged: (value) {
                      setState(() {
                        _locationSharing = value;
                      });
                      _saveSetting('pasahero_location', value);
                    },
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.visibility),
                  title: const Text('Profile Visibility'),
                  subtitle: const Text('Control who can see your profile'),
                  onTap: () => _showComingSoon('Profile Visibility Settings'),
                ),
                ListTile(
                  leading: const Icon(Icons.security),
                  title: const Text('Privacy Settings'),
                  onTap: () => _showComingSoon('Privacy Settings'),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Ride Preferences
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text(
                    'Ride Preferences',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.favorite),
                  title: const Text('Favorite Routes'),
                  subtitle: const Text('Save your frequently used routes'),
                  onTap: () => _showComingSoon('Favorite Routes'),
                ),
                ListTile(
                  leading: const Icon(Icons.accessibility),
                  title: const Text('Accessibility Needs'),
                  subtitle: const Text('Special requirements for rides'),
                  onTap: () => _showComingSoon('Accessibility Settings'),
                ),
                ListTile(
                  leading: const Icon(Icons.payment),
                  title: const Text('Payment Methods'),
                  subtitle: const Text('Manage your payment options'),
                  onTap: () => _showComingSoon('Payment Methods'),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Support
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text(
                    'Support',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.help),
                  title: const Text('Help & Support'),
                  onTap: () => _showComingSoon('Help & Support'),
                ),
                ListTile(
                  leading: const Icon(Icons.feedback),
                  title: const Text('Send Feedback'),
                  onTap: () => _showComingSoon('Feedback System'),
                ),
                ListTile(
                  leading: const Icon(Icons.info),
                  title: const Text('About PARA!'),
                  onTap: () => _showComingSoon('About Section'),
                ),
                ListTile(
                  leading: const Icon(Icons.description),
                  title: const Text('Terms of Service'),
                  onTap: () => _showComingSoon('Terms of Service'),
                ),
                ListTile(
                  leading: const Icon(Icons.privacy_tip),
                  title: const Text('Privacy Policy'),
                  onTap: () => _showComingSoon('Privacy Policy'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}