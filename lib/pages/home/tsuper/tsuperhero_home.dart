// lib/pages/tsuper/tsuperhero_home.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:para2/pages/login/login.dart';
import 'package:para2/pages/home/shared_home.dart';

class TsuperheroHome extends StatefulWidget {
  const TsuperheroHome({super.key});

  @override
  State<TsuperheroHome> createState() => _TsuperheroHomeState();
}

class _TsuperheroHomeState extends State<TsuperheroHome> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String _plateNumber = 'DRVR-XXX';
  bool _isOnline = false;

  @override
  void initState() {
    super.initState();
    _loadPlateNumber();
  }

  Future<void> _loadPlateNumber() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final doc = await _firestore.collection('users').doc(user.uid).get();
      if (doc.exists) {
        setState(() {
          _plateNumber = (doc.data()?['plateNumber'] ?? 'DRVR-XXX') as String;
        });
      }
    } catch (e) {
      debugPrint('Failed to load plate number: $e');
    }
  }

  Future<void> _handleSignOut() async {
    await _auth.signOut();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
    );
  }

  void _toggleOnlineStatus() async {
    setState(() => _isOnline = !_isOnline);

    try {
      final user = _auth.currentUser;
      if (user != null) {
        await _firestore.collection('users').doc(user.uid).update({
          'isOnline': _isOnline,
          'lastStatusChange': FieldValue.serverTimestamp(),
        });
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isOnline ? '🟢 You are now ONLINE' : '🔴 You are now OFFLINE',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      debugPrint('Error updating online status: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return SharedHome(
      roleLabel: 'TSUPERHERO',
      onSignOut: _handleSignOut,
      roleContent: _buildDriverContent(),
      roleMenu: _buildDriverMenu(),
    );
  }

  /// 🚌 Main driver action button
  Widget _buildDriverContent() {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 40.0),
        child: ElevatedButton.icon(
          onPressed: _toggleOnlineStatus,
          style: ElevatedButton.styleFrom(
            backgroundColor:
            _isOnline ? Colors.redAccent : const Color.fromARGB(255, 73, 172, 123),
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30),
            ),
          ),
          icon: Icon(_isOnline ? Icons.power_settings_new : Icons.play_arrow, color: Colors.white),
          label: Text(
            _isOnline ? 'Go Offline' : 'Go Online',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
          ),
        ),
      ),
    );
  }

  /// ⚙️ Driver-specific menu
  List<Widget> _buildDriverMenu() {
    return [
      ListTile(
        leading: const Icon(Icons.qr_code_scanner),
        title: const Text('Scan Activation QR'),
        onTap: () {
          // Future improvement: Navigate to QR activation screen
        },
      ),
      ListTile(
        leading: const Icon(Icons.route),
        title: const Text('Assigned Route'),
        onTap: () {},
      ),
      ListTile(
        leading: const Icon(Icons.person),
        title: const Text('Profile Settings'),
        onTap: () {
          // open profile settings
        },
      ),
      ListTile(
        leading: const Icon(Icons.settings),
        title: const Text('App Settings'),
        onTap: () {},
      ),
    ];
  }
}