import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ProfileSettingsPage extends StatefulWidget {
  const ProfileSettingsPage({super.key});

  @override
  State<ProfileSettingsPage> createState() => _ProfileSettingsPageState();
}

class _ProfileSettingsPageState extends State<ProfileSettingsPage> {
  final _usernameController = TextEditingController();
  final _contactController = TextEditingController();
  DateTime? _dob;

  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  bool _isSaving = false;
  bool _isLoading = true;

  // ✅ ADDED: Track completion status
  bool _hasUsername = false;
  bool _hasContact = false;
  bool _hasDOB = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final doc = await _firestore.collection('users').doc(user.uid).get();
      if (doc.exists) {
        final data = doc.data() ?? {};
        _usernameController.text = data['userName'] ?? '';
        _contactController.text = data['contact'] ?? '';
        if (data['dob'] != null && data['dob'] is Timestamp) {
          _dob = (data['dob'] as Timestamp).toDate();
        }

        // ✅ ADDED: Update completion status
        setState(() {
          _hasUsername = _usernameController.text.trim().isNotEmpty;
          _hasContact = _contactController.text.trim().isNotEmpty;
          _hasDOB = _dob != null;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('⚠️ Error loading profile: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveProfile() async {
    final user = _auth.currentUser;
    if (user == null) return;

    if (_usernameController.text.trim().isEmpty ||
        _contactController.text.trim().isEmpty ||
        _dob == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all fields')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      await _firestore.collection('users').doc(user.uid).set({
        'userName': _usernameController.text.trim(),
        'contact': _contactController.text.trim(),
        'dob': Timestamp.fromDate(_dob!),
      }, SetOptions(merge: true));

      // ✅ ADDED: Update completion status
      setState(() {
        _hasUsername = true;
        _hasContact = true;
        _hasDOB = true;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Profile updated successfully')),
        );

        // ✅ ADDED: Navigate back after successful save
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (mounted) {
            Navigator.pop(context);
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Failed to save: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _contactController.dispose();
    super.dispose();
  }

  // ✅ ADDED: Progress indicator
  Widget _buildCompletionProgress() {
    final completed = [_hasUsername, _hasContact, _hasDOB].where((e) => e).length;
    final total = 3;
    final percentage = (completed / total * 100).round();

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: percentage == 100 ? Colors.green[50] : Colors.amber[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: percentage == 100 ? Colors.green : Colors.amber,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                percentage == 100 ? Icons.check_circle : Icons.info,
                color: percentage == 100 ? Colors.green : Colors.amber,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  percentage == 100
                      ? 'Profile Complete! 🎉'
                      : 'Complete your profile to use PARA!',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: percentage == 100 ? Colors.green : Colors.amber[800],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: completed / total,
            backgroundColor: Colors.grey[300],
            color: percentage == 100 ? Colors.green : Colors.amber,
          ),
          const SizedBox(height: 4),
          Text(
            '$completed/$total fields completed ($percentage%)',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile Settings'),
        backgroundColor: const Color.fromARGB(255, 73, 172, 123),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              // ✅ ADDED: Completion progress
              _buildCompletionProgress(),

              TextField(
                controller: _usernameController,
                decoration: InputDecoration(
                  labelText: 'Preferred Username',
                  border: const OutlineInputBorder(),
                  // ✅ ADDED: Completion indicator
                  suffixIcon: _hasUsername
                      ? const Icon(Icons.check_circle, color: Colors.green)
                      : const Icon(Icons.error, color: Colors.orange),
                ),
                onChanged: (value) {
                  setState(() {
                    _hasUsername = value.trim().isNotEmpty;
                  });
                },
              ),
              const SizedBox(height: 15),
              TextField(
                controller: _contactController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: 'Contact Number',
                  border: const OutlineInputBorder(),
                  // ✅ ADDED: Completion indicator
                  suffixIcon: _hasContact
                      ? const Icon(Icons.check_circle, color: Colors.green)
                      : const Icon(Icons.error, color: Colors.orange),
                ),
                onChanged: (value) {
                  setState(() {
                    _hasContact = value.trim().isNotEmpty;
                  });
                },
              ),
              const SizedBox(height: 15),
              ListTile(
                title: Text(
                  _dob == null
                      ? 'Select Date of Birth'
                      : 'DOB: ${_dob!.day}/${_dob!.month}/${_dob!.year}',
                  style: TextStyle(
                    color: _dob == null ? Colors.grey : Colors.black,
                  ),
                ),
                trailing: _hasDOB
                    ? const Icon(Icons.check_circle, color: Colors.green)
                    : const Icon(Icons.calendar_month, color: Colors.orange),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _dob ?? DateTime(2000),
                    firstDate: DateTime(1900),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null && mounted) {
                    setState(() {
                      _dob = picked;
                      _hasDOB = true;
                    });
                  }
                },
              ),
              const SizedBox(height: 30),
              SizedBox(
                width: 200,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _saveProfile,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color.fromARGB(255, 73, 172, 123),
                  ),
                  child: _isSaving
                      ? const CircularProgressIndicator(
                    color: Colors.white,
                  )
                      : const Text(
                    'Save Changes',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}