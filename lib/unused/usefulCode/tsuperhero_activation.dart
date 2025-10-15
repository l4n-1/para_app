// lib/pages/unused/usefulCode/tsuperhero_activation.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:qr_code_scanner/qr_code_scanner.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:para2/pages/login/signup_tsuperhero.dart';
import 'package:para2/pages/login/plate_number_input.dart';

class TsuperheroActivationPage extends StatefulWidget {
  const TsuperheroActivationPage({super.key});

  @override
  State<TsuperheroActivationPage> createState() =>
      _TsuperheroActivationPageState();
}

class _TsuperheroActivationPageState extends State<TsuperheroActivationPage> {
  final GlobalKey qrKey = GlobalKey(debugLabel: 'QR');
  QRViewController? controller;
  bool _processing = false;

  @override
  void reassemble() {
    super.reassemble();
    controller?.pauseCamera();
    controller?.resumeCamera();
  }

  void _onQRViewCreated(QRViewController ctrl) {
    controller = ctrl;

    controller!.scannedDataStream.listen((scanData) async {
      if (_processing) return;
      _processing = true;

      try {
        final raw = scanData.code;
        if (raw == null || raw.trim().isEmpty) {
          _showMessage('⚠️ Scanned empty or unreadable QR code.');
          await controller?.resumeCamera();
          _processing = false;
          return;
        }

        // Expect JSON {"deviceId": "box-0001"} or plain "box-0001"
        String? deviceId;
        try {
          final decoded = json.decode(raw);
          if (decoded is Map && decoded['deviceId'] != null) {
            deviceId = decoded['deviceId'].toString();
          }
        } catch (_) {
          final plain = raw.trim();
          if (plain.isNotEmpty) deviceId = plain;
        }

        if (deviceId == null || deviceId.isEmpty) {
          _showMessage('⚠️ Invalid QR code contents.');
          await controller?.resumeCamera();
          _processing = false;
          return;
        }

        // ✅ Validate deviceId from Firebase Realtime Database
        final dbRef = FirebaseDatabase.instance.ref('devices/$deviceId');
        final snapshot = await dbRef.get();

        if (!snapshot.exists) {
          _showMessage('❌ This QR is not registered.');
          await controller?.resumeCamera();
          _processing = false;
          return;
        }

        final deviceData = snapshot.value as Map?;
        final valid = deviceData?['valid'] == true;
        final assigned = deviceData?['assigned'] == true;

        if (!valid) {
          _showMessage('❌ This QR code is not authorized.');
          await controller?.resumeCamera();
          _processing = false;
          return;
        }

        if (assigned) {
          _showMessage('⚠️ This QR code is already used by another driver.');
          await controller?.resumeCamera();
          _processing = false;
          return;
        }

        // Pause camera before proceeding
        await controller?.pauseCamera();

        final user = FirebaseAuth.instance.currentUser;

        if (user != null) {
          // Logged in → go to PlateNumberInputPage
          if (!mounted) return;
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => PlateNumberInputPage(deviceId: deviceId!),
            ),
          );
        } else {
          // Not logged in → go to SignupTsuperhero
          if (!mounted) return;
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => SignupTsuperhero(deviceId: deviceId!),
            ),
          );
        }
      } catch (e) {
        _showMessage('❌ QR handling error: $e');
        await controller?.resumeCamera();
      } finally {
        _processing = false;
      }
    });
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Activate as TsuperHero'),
      ),
      body: Column(
        children: [
          Expanded(
            flex: 4,
            child: QRView(
              key: qrKey,
              onQRViewCreated: _onQRViewCreated,
              overlay: QrScannerOverlayShape(
                borderRadius: 8,
                borderColor: Colors.green,
                borderLength: 24,
                borderWidth: 8,
                cutOutSize: MediaQuery.of(context).size.width * 0.7,
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: Center(
              child: Text(
                'Point camera to the box QR code',
                style: TextStyle(fontSize: 16, color: Colors.grey[700]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}