import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:para2/pages/home/shared_home.dart';
import 'package:para2/pages/login/login.dart';
import 'package:para2/pages/login/qr_scan_page.dart';

class PasaheroHome extends StatefulWidget {
  const PasaheroHome({super.key});

  @override
  State<PasaheroHome> createState() => _PasaheroHomeState();
}

class _PasaheroHomeState extends State<PasaheroHome> {
  final FirebaseAuth _auth = FirebaseAuth.instance;

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
      roleLabel: 'PASAHERO',
      onSignOut: _handleSignOut,
      roleContent: _buildPasaheroContent(),
      roleMenu: _buildPasaheroMenu(),
    );
  }

  /// 🟢 Main pasahero area (PARA! button)
  Widget _buildPasaheroContent() {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 40.0),
        child: ElevatedButton(
          onPressed: () {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('PARA! tapped!')));
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.greenAccent.shade700,
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30),
            ),
          ),
          child: const Text(
            'PARA!',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  /// ⚙️ Pasahero-specific menu
  List<Widget> _buildPasaheroMenu() {
    return [
      ListTile(
        leading: const Icon(Icons.history),
        title: const Text('Trip History'),
        onTap: () {},
      ),
      ListTile(
        leading: const Icon(Icons.settings),
        title: const Text('Settings'),
        onTap: () {},
      ),
      ListTile(
        leading: const Icon(Icons.help),
        title: const Text('Help'),
        onTap: () {},
      ),
      ListTile(
        leading: const Icon(Icons.qr_code_2),
        title: const Text('Scan QR to Become Tsuperhero'),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const QRScanPage()),
          );
        },
      ),
    ];
  }
}
