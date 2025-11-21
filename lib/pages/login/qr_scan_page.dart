import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:para2/pages/home/role_router.dart';
import 'package:para2/pages/login/signup_tsuperhero.dart';
import 'package:para2/services/snackbar_service.dart';

class QRScanPage extends StatefulWidget {
  const QRScanPage({super.key});

  @override
  State<QRScanPage> createState() => _QRScanPageState();
}

class _QRScanPageState extends State<QRScanPage> {
  final MobileScannerController _controller = MobileScannerController();
  final ImagePicker _imagePicker = ImagePicker();
  bool _isProcessing = false;
  // Track recently scanned device IDs to debounce repeated detections
  final Map<String, DateTime> _recentScans = {};

  // 🔗 Replace this with your deployed Firebase Function URL
  final String functionUrl = "https://claimbaryabox-elu2otbf7q-uc.a.run.app";

  // Call the claim function with JSON body and return parsed result map
  Future<Map<String, dynamic>> _callClaimFunction(String deviceId, String uid) async {
    try {
      final uri = Uri.parse(functionUrl);
      final body = jsonEncode({'deviceId': deviceId, 'uid': uid});
      final resp = await http
          .post(uri, headers: {'Content-Type': 'application/json'}, body: body)
          .timeout(const Duration(seconds: 15));

      final status = resp.statusCode;
      final respBody = resp.body;
      debugPrint('➡️ POST ${uri.toString()} status=$status body=$respBody');
      if (status != 200) {
        return {'success': false, 'status': status, 'message': 'HTTP ${status}: ${respBody}'};
      }

      try {
        final parsed = jsonDecode(respBody);
        if (parsed is Map<String, dynamic>) return parsed;
        return {'success': false, 'message': 'Invalid response format', 'raw': respBody};
      } catch (e) {
        return {'success': false, 'message': 'JSON parse error: $e', 'raw': respBody};
      }
    } catch (e) {
      debugPrint('❌ Network error calling claim function: $e');
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  Future<void> _handleQRCode(String code) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    try {
      // Stop scanner while processing
      try {
        _controller.stop();
      } catch (_) {}

      final auth = FirebaseAuth.instance;
      final currentUser = auth.currentUser;
      debugPrint('🔑 currentUser uid = ${currentUser?.uid}');

      debugPrint("📦 Raw scanned QR: $code");

      // Parse JSON or fallback to plain deviceId
      String deviceId;
      try {
        final parsed = jsonDecode(code);
        deviceId = parsed['deviceId'] ?? code.trim();
      } catch (_) {
        deviceId = code.trim();
      }

      debugPrint("✅ Parsed Device ID: $deviceId");

      // Debounce repeated scans
      final now = DateTime.now();
      final last = _recentScans[deviceId];
      if (last != null && now.difference(last) < const Duration(seconds: 5)) {
        debugPrint('Ignored duplicate scan for $deviceId (debounced)');
        return;
      }
      _recentScans[deviceId] = now;

      if (currentUser == null) {
        // Not signed in — go to signup (pass normalized ID)
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => SignupTsuperhero(deviceId: deviceId.toLowerCase()),
          ),
        );
        return;
      }

      final uid = currentUser.uid;
      final normalizedDeviceId = deviceId.toLowerCase();

      // Call backend function
      final result = await _callClaimFunction(normalizedDeviceId, uid);
      debugPrint("🌐 Function response: $result");

      if (result['success'] == true) {
        // SECURITY CHECK: ensure Firestore user doc exists
        final userDocRef = FirebaseFirestore.instance.collection('users').doc(uid);
        final userDoc = await userDocRef.get();

        if (!userDoc.exists) {
          SnackbarService.show(context,
              'Account record missing. Please sign up again or contact support.');
          try {
            await FirebaseAuth.instance.signOut();
          } catch (_) {}
          return;
        }

        // Update Firestore user merge
        await userDocRef.set({
          'role': 'tsuperhero',
          'boxClaimed': normalizedDeviceId,
        }, SetOptions(merge: true));

        SnackbarService.show(context, result['message'] ?? 'Claimed $normalizedDeviceId successfully!');

        // Redirect to dashboard
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const RoleRouter()),
        );
      } else {
        SnackbarService.show(context, '❌ Failed: ${result['message'] ?? 'Unknown error'}');
      }
    } catch (e) {
      debugPrint("⚠️ Error in QR handler: $e");
      SnackbarService.show(context, 'Error: $e');
    } finally {
      setState(() => _isProcessing = false);
      try {
        _controller.start();
      } catch (_) {}
    }
  }

  // ✅ ADDED: Gallery image picker for QR scanning
  Future<void> _pickImageFromGallery() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
        maxHeight: 800,
      );

      if (image != null) {
        setState(() => _isProcessing = true);

        // Show processing message
        SnackbarService.show(context, '🔍 Scanning image for QR code...', duration: const Duration(seconds: 2));

        // Simulate QR code processing (in real app, use QR decoding library)
        await Future.delayed(const Duration(seconds: 2));

        // For demo purposes - show instruction
        SnackbarService.show(context, '📸 In production: QR would be decoded from gallery image');

        // Demo: Simulate finding a QR code
        _showGalleryQRDemo();
      }
    } catch (e) {
      SnackbarService.show(context, '❌ Error picking image: $e');
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  void _showGalleryQRDemo() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Gallery QR Scan Demo'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.qr_code, size: 50, color: Colors.blue),
            SizedBox(height: 16),
            Text(
              'In the full app, this would decode a QR code from your gallery image and process it automatically.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
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
        child: Column(
          children: [
            // Camera Scanner
            Expanded(
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

            const SizedBox(height: 20),

            // ✅ ADDED: Gallery Option Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isProcessing ? null : _pickImageFromGallery,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.photo_library, color: Colors.white),
                label: const Text(
                  'Select from Gallery',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 10),

            // Help Text
            const Text(
              'Point camera at QR code or select from gallery',
              style: TextStyle(
                color: Colors.black54,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}