import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:para2/pages/home/role_router.dart';
import 'package:para2/pages/login/tsuperhero_signup_page.dart';

class QRScanPage extends StatefulWidget {
  const QRScanPage({super.key});

  @override
  State<QRScanPage> createState() => _QRScanPageState();
}

class _QRScanPageState extends State<QRScanPage> {
  final MobileScannerController _controller = MobileScannerController();
  bool _isProcessing = false;

  Future<void> _handleQRCode(String code) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    try {
      final firestore = FirebaseFirestore.instance;
      final auth = FirebaseAuth.instance;

      // Assume QR code contains a unique jeepney or driver ID
      final scannedId = code.trim();
      debugPrint("Scanned QR: $scannedId");

      final currentUser = auth.currentUser;

      if (currentUser != null) {
        // ✅ Already logged in — promote to tsuperhero
        await firestore.collection('users').doc(currentUser.uid).set({
          'role': 'tsuperhero',
          'linkedJeepneyId': scannedId, // optional
        }, SetOptions(merge: true));

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Your role has been updated to Tsuperhero!'),
          ),
        );

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const RoleRouter()),
        );
      } else {
        // 🆕 Not logged in — redirect to signup with QR info
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => TsuperheroSignupPage(scannedId: scannedId),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Tsuper QR'),
        backgroundColor: const Color.fromARGB(255, 73, 172, 123),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: MobileScanner(
                  controller: _controller,
                  onDetect: (capture) {
                    final barcode = capture.barcodes.first;
                    final String? rawValue = barcode.rawValue;
                    if (rawValue != null) _handleQRCode(rawValue);
                  },
                ),
              ),
            ),

            if (_isProcessing)
              const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
          ],
        ),
      ),
    );
  }
}
