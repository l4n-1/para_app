// lib/pages/plate_number_input.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:para2/services/firebase_services.dart';
import 'package:para2/pages/home/tsuper/tsuperhero_home.dart';

class PlateNumberInputPage extends StatefulWidget {
  final String deviceId;
  const PlateNumberInputPage({super.key, required this.deviceId});

  @override
  State<PlateNumberInputPage> createState() => _PlateNumberInputPageState();
}

class _PlateNumberInputPageState extends State<PlateNumberInputPage> {
  final _plateController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final FirebaseService _fs = FirebaseService();
  bool _isSaving = false;

  // Plate pattern: 3 uppercase letters + 4 digits, optional single space allowed (e.g. ABC1234 or ABC 1234)
  final RegExp _plateRegex = RegExp(r'^[A-Z]{3}\s?\d{4}$');

  @override
  void dispose() {
    _plateController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No authenticated user found')));
        return;
      }
      final plate = _plateController.text.trim().toUpperCase();
      await _fs.updateUserRoleAndHardware(
        uid: user.uid,
        role: 'tsuperhero',
        hardwareId: widget.deviceId,
        plateNumber: plate,
      );
      // redirect
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const TsuperheroHome()));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to upgrade: $e')));
    } finally {
      setState(() => _isSaving = false);
    }
  }

  String? _validatePlate(String? value) {
    if (value == null || value.trim().isEmpty) return 'Please enter plate number';
    final v = value.trim().toUpperCase();
    if (!_plateRegex.hasMatch(v)) return 'Invalid plate. Use ABC1234';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Enter Plate Number'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              const Text('Confirm your jeep plate number to activate driver mode.'),
              const SizedBox(height: 16),
              Form(
                key: _formKey,
                child: TextFormField(
                  controller: _plateController,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    hintText: 'ABC1234',
                    labelText: 'Plate Number',
                  ),
                  validator: _validatePlate,
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _isSaving ? null : _submit,
                child: _isSaving ? const CircularProgressIndicator() : const Text('Activate'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}