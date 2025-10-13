// lib/pages/tsuperhero_home.dart
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
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SharedHome(
      displayName: _plateNumber,
      roleLabel: 'TSUPERHERO',
      onSignOut: _handleSignOut,
      roleContent: _buildDriverContent(),
      roleMenu: _buildDriverMenu(),
    );
  }

  /// 🚌 Main driver area (inside map area)
  Widget _buildDriverContent() {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 40.0),
        child: ElevatedButton.icon(
          onPressed: () {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('Go Online tapped!')));
          },
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30),
            ),
          ),
          icon: const Icon(Icons.power_settings_new),
          label: const Text(
            'Go Online',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
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
          // TODO: implement QR activation
        },
      ),
      ListTile(
        leading: const Icon(Icons.route),
        title: const Text('Assigned Route'),
        onTap: () {},
      ),
      ListTile(
        leading: const Icon(Icons.settings),
        title: const Text('Settings'),
        onTap: () {},
      ),
    ];
  }
}
