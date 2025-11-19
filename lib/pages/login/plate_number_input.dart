// lib/pages/login/plate_number_input.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:para2/pages/home/role_router.dart';
import 'package:para2/pages/home/shared_home.dart';

class PlateNumberInputPage extends StatefulWidget {
  final String deviceId;

  const PlateNumberInputPage({super.key, required this.deviceId});

  @override
  State<PlateNumberInputPage> createState() => _PlateNumberInputPageState();
}

class _PlateNumberInputPageState extends State<PlateNumberInputPage> {
  final TextEditingController _plateController = TextEditingController();
  bool _isSubmitting = false;

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseDatabase _database = FirebaseDatabase.instance;

  @override
  void dispose() {
    _plateController.dispose();
    super.dispose();
  }

  Future<void> _submitPlate() async {
    final plate = _plateController.text.trim().toUpperCase();

    if (plate.isEmpty || plate.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("⚠️ Please enter a valid plate number.")),
      );
      return;
    }

    final user = _auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("❌ No user found. Please log in again.")),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      // 🔹 1. Update Firestore user role & plate number
      await _firestore.collection('users').doc(user.uid).set({
        'role': 'tsuperhero',
        'plateNumber': plate,
        'deviceId': widget.deviceId,
        'activatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // 🔹 2. Mark the device as assigned in Realtime Database
      await _database.ref('devices/${widget.deviceId}').update({
        'assigned': true,
        'userId': user.uid,
        'activatedAt': ServerValue.timestamp,
      });

      // 🔹 3. Confirmation message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ TsuperHero activation successful!')),
      );

      // 🔹 4. Navigate to SharedHome (driver view)
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const RoleRouter()),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('❌ Activation failed: $e')));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 240, 240, 240),
      appBar: AppBar(
        title: const Text("TsuperHero Activation"),
        centerTitle: true,
        backgroundColor: const Color.fromARGB(255, 73, 172, 123),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              "Enter your Plate Number",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _plateController,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                hintText: "e.g. ABC 1234",
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                filled: true,
                fillColor: Colors.white,
              ),
            ),
            const SizedBox(height: 30),
            SizedBox(
              width: 200,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submitPlate,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color.fromARGB(255, 73, 172, 123),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 40,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
                child: _isSubmitting
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text(
                        "Activate",
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
