// lib/pages/tsuperhero_activation.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';

class TsuperheroActivationPage extends StatefulWidget {
  const TsuperheroActivationPage({super.key});

  @override
  State<TsuperheroActivationPage> createState() => _TsuperheroActivationPageState();
}

class _TsuperheroActivationPageState extends State<TsuperheroActivationPage> {
  bool _scanning = true;
  String? _message;
  MobileScannerController cameraController = MobileScannerController();

  // TODO: Replace with your deployed Cloud Function endpoint
  static const String claimEndpoint = 'https://us-central1-paratotype.cloudfunctions.net/claimBaryaBox';

  // Called when QR code scanned
  Future<void> _onDetect(BarcodeCapture capture) async {
    if (!_scanning) return;
    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final raw = barcodes.first.rawValue;
    if (raw == null || raw.isEmpty) return;

    setState(() {
      _scanning = false;
      _message = 'Processing QR...';
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Not signed in');

      // The QR should contain a deviceId or token (e.g., {"deviceId":"box-12345"})
      // Accept either plain deviceId or json encoded payload.
      String deviceId = raw;
      try {
        final parsed = json.decode(raw);
        if (parsed is Map && parsed['deviceId'] != null) {
          deviceId = parsed['deviceId'].toString();
        }
      } catch (_) {
        // raw not JSON, keep as is
      }

      // Call backend endpoint to claim the barya box
      final resp = await http.post(
        Uri.parse(claimEndpoint),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'deviceId': deviceId, 'uid': user.uid}),
      );

      if (resp.statusCode == 200) {
        final data = json.decode(resp.body);
        final success = data['success'] == true;
        final msg = data['message'] ?? 'Claimed';
        if (success) {
          setState(() => _message = 'Activation successful: $msg');
          // optionally navigate to TsuperheroHome or refresh
        } else {
          setState(() => _message = 'Activation failed: $msg');
          // allow re-scan
          await Future.delayed(const Duration(seconds: 2));
          setState(() {
            _scanning = true;
            _message = null;
          });
        }
      } else {
        setState(() => _message = 'Server error: ${resp.statusCode}');
      }
    } catch (e) {
      setState(() => _message = 'Error: $e');
    }
  }

  @override
  void dispose() {
    cameraController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // No appbar, match pasahero style
      body: SafeArea(
        child: Stack(
          children: [
            MobileScanner(
              controller: cameraController,
              allowDuplicates: false,
              onDetect: (capture) => _onDetect(capture),
            ),
            Positioned(
              top: 16,
              left: 16,
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            if (_message != null)
              Positioned(
                bottom: 34,
                left: 20,
                right: 20,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _message!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              )
            else
              Positioned(
                bottom: 34,
                left: 20,
                right: 20,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Point camera to the QR code on the barya box to activate driver role',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              )
          ],
        ),
      ),
    );
  }
}