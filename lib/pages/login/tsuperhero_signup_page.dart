// lib/pages/login/tsuperhero_signup_page.dart
import 'package:flutter/material.dart';
import 'package:para2/pages/login/signup_step2.dart';

class TsuperheroSignupPage extends StatefulWidget {
  final String scannedId;
  const TsuperheroSignupPage({super.key, required this.scannedId});

  @override
  State<TsuperheroSignupPage> createState() => _TsuperheroSignupPageState();
}

class _TsuperheroSignupPageState extends State<TsuperheroSignupPage> {
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _userNameController = TextEditingController();
  DateTime? _selectedDOB;

  Future<void> _pickDOB() async {
    DateTime now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year - 18),
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (picked != null) setState(() => _selectedDOB = picked);
  }

  void _goToNextStep() {
    if (_firstNameController.text.isEmpty ||
        _lastNameController.text.isEmpty ||
        _userNameController.text.isEmpty ||
        _selectedDOB == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please complete all required fields')),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SignupStep2(
          firstName: _firstNameController.text.trim(),
          lastName: _lastNameController.text.trim(),
          userName: _userNameController.text.trim(),
          dob: _selectedDOB!,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 233, 233, 231),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            children: [
              const SizedBox(height: 80),
              Image.asset('assets/Paralogotemp.png', height: 150, width: 150),
              const SizedBox(height: 40),
              const Text(
                'Tsuperhero Registration',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              Text(
                'Linked Jeepney ID: ${widget.scannedId}',
                style: const TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _firstNameController,
                decoration: InputDecoration(
                  hintText: 'First Name',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(25),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: Colors.grey[200],
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _lastNameController,
                decoration: InputDecoration(
                  hintText: 'Last Name',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(25),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: Colors.grey[200],
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _userNameController,
                decoration: InputDecoration(
                  hintText: 'Username',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(25),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: Colors.grey[200],
                ),
              ),
              const SizedBox(height: 10),
              GestureDetector(
                onTap: _pickDOB,
                child: Container(
                  height: 60,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(25),
                  ),
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _selectedDOB == null
                        ? 'Select Date of Birth'
                        : '${_selectedDOB!.year}-${_selectedDOB!.month}-${_selectedDOB!.day}',
                  ),
                ),
              ),
              const SizedBox(height: 30),
              ElevatedButton(
                onPressed: _goToNextStep,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color.fromARGB(255, 73, 172, 123),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(25),
                  ),
                ),
                child: const Text('Next'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
