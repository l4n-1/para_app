import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
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

  // 🔗 Replace this with your deployed Firebase Function URL
  final String functionUrl = "https://claimbaryabox-elu2otbf7q-uc.a.run.app";

  Future<void> _handleQRCode(String code) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    try {
      final auth = FirebaseAuth.instance;
      final currentUser = auth.currentUser;

      debugPrint("📦 Raw scanned QR: $code");

      // ✅ Parse JSON or fallback to plain deviceId
      String deviceId;
      try {
        final parsed = jsonDecode(code);
        deviceId = parsed['deviceId'] ?? code.trim();
      } catch (_) {
        deviceId = code.trim();
      }

      debugPrint("✅ Parsed Device ID: $deviceId");

      if (currentUser == null) {
        // 🔐 Redirect to signup if not logged in
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => TsuperheroSignupPage(scannedId: deviceId),
          ),
        );
        return;
      }

      // ✅ Send claim request
      final uid = currentUser.uid;
      final response = await http.post(
        Uri.parse(functionUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'deviceId': deviceId, 'uid': uid}),
      );

      final result = jsonDecode(response.body);
      debugPrint("🌐 Function response: $result");

      if (response.statusCode == 200 && result['success'] == true) {
        // ✅ Update Firestore user data
        await FirebaseFirestore.instance.collection('users').doc(uid).set({
          'role': 'tsuperhero',
          'boxClaimed': deviceId,
        }, SetOptions(merge: true));

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result['message'] ?? 'Claimed $deviceId successfully!',
            ),
          ),
        );

        // ✅ Redirect to dashboard
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const RoleRouter()),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Failed: ${result['message'] ?? 'Unknown error'}'),
          ),
        );
      }
    } catch (e) {
      debugPrint("⚠️ Error: $e");
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
