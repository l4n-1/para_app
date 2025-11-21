// lib/pages/login/signup_tsuperhero.dart
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:para2/pages/home/tsuper/tsuperhero_home.dart';
import 'package:para2/services/snackbar_service.dart';

class SignupTsuperhero extends StatefulWidget {
  /// deviceId can be passed from QR scanner; if null, user may manually enter it.
  final String? deviceId;
  const SignupTsuperhero({super.key, this.deviceId});

  @override
  State<SignupTsuperhero> createState() => _SignupTsuperheroState();
}

class _SignupTsuperheroState extends State<SignupTsuperhero> {
  final _formKey = GlobalKey<FormState>();

  // Controllers
  final TextEditingController _firstController = TextEditingController();
  final TextEditingController _lastController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _contactController = TextEditingController();
  final TextEditingController _plateController = TextEditingController();
  final TextEditingController _deviceController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  bool _isLoading = false;
  Timer? _emailCheckTimer;
  Timer? _resendThrottleTimer;
  bool _canResend = true;

  // Show/hide password
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  // Validation regexes
  final RegExp _contactRegex = RegExp(r'^09\d{9}$');
  final RegExp _plateRegex = RegExp(r'^[A-Z]{3}\s?\d{3,4}$');
  final RegExp _passwordRegex = RegExp(r'^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[@$!%*?&])[A-Za-z\d@$!%*?&]{8,}$');

  @override
  void initState() {
    super.initState();
    // Prefill deviceId if provided by QR
    if (widget.deviceId != null && widget.deviceId!.trim().isNotEmpty) {
      _deviceController.text = widget.deviceId!;
    }
  }

  @override
  void dispose() {
    _firstController.dispose();
    _lastController.dispose();
    _usernameController.dispose();
    _contactController.dispose();
    _plateController.dispose();
    _deviceController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();

    _emailCheckTimer?.cancel();
    _resendThrottleTimer?.cancel();
    super.dispose();
  }

  InputDecoration _inputDecoration(String hintText, {String? errorText, bool isPassword = false, VoidCallback? onToggleVisibility, bool obscureText = true}) {
    return InputDecoration(
      hintText: hintText,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(25),
        borderSide: BorderSide.none,
      ),
      filled: true,
      fillColor: Colors.grey[200],
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      errorText: errorText,
      errorStyle: const TextStyle(color: Colors.red, fontSize: 12),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(25),
        borderSide: const BorderSide(color: Colors.red),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(25),
        borderSide: const BorderSide(color: Colors.red),
      ),
      suffixIcon: isPassword
          ? IconButton(
              icon: Icon(obscureText ? Icons.visibility_off : Icons.visibility, color: Colors.grey[600]),
              onPressed: onToggleVisibility,
            )
          : null,
    );
  }

  void _showSnack(String message) {
    if (!mounted) return;
    SnackbarService.show(context, message);
  }

  Future<bool> _isUsernameTaken(String username) async {
    final q = await _db.collection('users').where('username', isEqualTo: username).limit(1).get();
    return q.docs.isNotEmpty;
  }

  Future<bool> _isPlateTaken(String plate) async {
    final q = await _db.collection('users').where('plateNumber', isEqualTo: plate).limit(1).get();
    return q.docs.isNotEmpty;
  }

  Future<bool> _isDeviceLinked(String deviceId) async {
    final q = await _db.collection('users').where('deviceId', isEqualTo: deviceId).limit(1).get();
    return q.docs.isNotEmpty;
  }

  Future<bool> _isDeviceReal(String deviceId) async {
    final q = await _db.collection('baryaBoxes').where('deviceId', isEqualTo: deviceId).limit(1).get();
    return q.docs.isNotEmpty;
  }

  Future<void> _attemptSignup() async {
    // Validate form
    if (!_formKey.currentState!.validate()) {
      _showSnack('Please fix the errors in the form.');
      return;
    }

    final first = _firstController.text.trim();
    final last = _lastController.text.trim();
    final username = _usernameController.text.trim();
    final contact = _contactController.text.trim();
    final plate = _plateController.text.trim();
    final deviceId = _deviceController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    setState(() => _isLoading = true);

    try {
      // Uniqueness checks (case-sensitive, as required)
      if (await _isUsernameTaken(username)) {
        _showSnack('Username already exists. Please choose another.');
        setState(() => _isLoading = false);
        return;
      }

      if (await _isPlateTaken(plate)) {
        _showSnack('Plate number already registered. If this is your plate, contact admin.');
        setState(() => _isLoading = false);
        return;
      }

      if (await _isDeviceLinked(deviceId)) {
        _showSnack('This device is already linked to another account.');
        setState(() => _isLoading = false);
        return;
      }

      if (!await _isDeviceReal(deviceId)) {
        _showSnack('No records found for this device ID.');
        setState(() => _isLoading = false);
        return;
      }
      // Create auth user
      final userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final uid = userCredential.user!.uid;

      // Write Firestore document
      await _db.collection('users').doc(uid).set({
        'firstName': first,
        'lastName': last,
        'username': username,
        'contactNumber': contact,
        'plateNumber': plate,
        'deviceId': deviceId,
        'email': email,
        'role': 'tsuperhero',
        'createdAt': FieldValue.serverTimestamp(),
      });

      await _db.collection('baryaBoxes').doc(deviceId).set({
        'claimedAt': FieldValue.serverTimestamp(),
        'claimedBy': uid,
        'deviceId': deviceId,
        'status': 'claimed',
        
      });

      // Send verification email
      await userCredential.user!.sendEmailVerification();

      // Show verification dialog (with resend)
      if (!mounted) return;
      _showVerificationDialog(userCredential.user!);
    } on FirebaseAuthException catch (e) {
      // If the account creation fails, try to delete any partial user (rare case)
      _showSnack('Sign up failed: ${e.message}');
    } catch (e) {
      _showSnack('Sign up failed: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showVerificationDialog(User user) {
    // throttle for resend button
    _canResend = true;
    _resendThrottleTimer?.cancel();

    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.6),
      builder: (_) {
        // Start polling every 3 seconds to see if email is verified
        _emailCheckTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
          try {
            await user.reload();
            final refreshed = _auth.currentUser;
            if (refreshed != null && refreshed.emailVerified) {
              _emailCheckTimer?.cancel();
              _resendThrottleTimer?.cancel();
              if (!mounted) return;
              Navigator.of(context).pop(); // close popup
              // Navigate to tsuperhero home
              if (!mounted) return;
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const TsuperheroHome()),
              );
            }
          } catch (e) {
            // ignore reload errors silently; will try again
          }
        });

        return StatefulBuilder(builder: (context, setStateDialog) {
          // We will control resend button enable via outer _canResend and setStateDialog to re-render
          return Center(
            child: Container(
              padding: const EdgeInsets.all(20),
              width: 300,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                boxShadow: const [
                  BoxShadow(color: Colors.black26, blurRadius: 10, spreadRadius: 2)
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(
                    color: Color.fromARGB(255, 73, 172, 123),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    "Verification email sent.\nPlease verify your email to continue.",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _canResend
                        ? () async {
                      try {
                        await user.sendEmailVerification();
                        _showSnack('Verification email resent.');
                        // throttle: disable for 15 seconds
                        _canResend = false;
                        setStateDialog(() {});
                        _resendThrottleTimer?.cancel();
                        _resendThrottleTimer = Timer(const Duration(seconds: 15), () {
                          _canResend = true;
                          if (mounted) setStateDialog(() {});
                        });
                      } catch (e) {
                        _showSnack('Failed to resend: $e');
                      }
                    }
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color.fromARGB(255, 73, 172, 123),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(
                      _canResend ? 'Resend Email' : 'Please wait...',
                      style: const TextStyle(color: Colors.black),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () async {
                      // allow manual close only if user wants to continue later
                      _emailCheckTimer?.cancel();
                      _resendThrottleTimer?.cancel();
                      if (!mounted) return;
                      Navigator.of(context).pop();
                    },
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ),
          );
        });
      },
    ).then((_) {
      // cleanup timers when popup closes
      _emailCheckTimer?.cancel();
      _resendThrottleTimer?.cancel();
      _canResend = true;
    });
  }

  String? _validateNotEmpty(String? v, String label) {
    if (v == null || v.trim().isEmpty) return '$label is required';
    return null;
  }

  String? _validateUsername(String? v) {
    if (v == null || v.trim().isEmpty) return 'Username is required';
    if (v.trim().length < 8) return 'Username must be at least 8 characters';
    return null;
  }

  String? _validateContact(String? v) {
    if (v == null || v.trim().isEmpty) return 'Contact is required';
    if (!_contactRegex.hasMatch(v.trim())) return 'Enter a valid PH contact (09XXXXXXXXX)';
    return null;
  }

  String? _validatePlate(String? v) {
    if (v == null || v.trim().isEmpty) return 'Plate number is required';
    if (!_plateRegex.hasMatch(v.trim())) {
      return 'Plate must be like ABC123 or ABC 1234 (uppercase letters required)';
    }
    return null;
  }

  String? _validateEmail(String? v) {
    if (v == null || v.trim().isEmpty) return 'Email is required';
    final pattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (!pattern.hasMatch(v.trim())) return 'Enter a valid email';
    return null;
  }

  String? _validatePassword(String? v) {
    if (v == null || v.isEmpty) return 'Password is required';
    if (!_passwordRegex.hasMatch(v)) {
      return 'For security, password should have at least:\n• 8+ characters\n• 1 uppercase letter\n• 1 lowercase letter\n• 1 number\n• 1 special character';
    }
    return null;
  }

  String? _validateConfirm(String? v) {
    if (v == null || v.isEmpty) return 'Confirm your password';
    if (v != _passwordController.text) return 'Passwords do not match';
    return null;
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 233, 233, 231),
      appBar: AppBar(
        title: const Text('TsuperHero Signup'),
        backgroundColor: const Color.fromARGB(0, 240, 241, 241),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                const SizedBox(height: 8),
                Image.asset('assets/Paralogotemp.png', height: 120, width: 120),
                const SizedBox(height: 12),

                // Name fields
                TextFormField(
                  controller: _firstController,
                  decoration: _inputDecoration('First name'),
                  validator: (v) => _validateNotEmpty(v, 'First name'),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _lastController,
                  decoration: _inputDecoration('Last name'),
                  validator: (v) => _validateNotEmpty(v, 'Last name'),
                ),
                const SizedBox(height: 10),

                // Username
                TextFormField(
                  controller: _usernameController,
                  decoration: _inputDecoration('Username (≥8 chars)'),
                  validator: _validateUsername,
                ),
                const SizedBox(height: 10),

                // Contact
                TextFormField(
                  controller: _contactController,
                  decoration: _inputDecoration('Contact Number (09XXXXXXXXX)'),
                  keyboardType: TextInputType.phone,
                  validator: _validateContact,
                ),
                const SizedBox(height: 10),

                // Plate number
                TextFormField(
                  controller: _plateController,
                  decoration: _inputDecoration('Plate Number (ABC123 / ABC 1234)'),
                  validator: _validatePlate,
                ),
                const SizedBox(height: 10),

                // Device ID - prefilled by QR, but editable
                TextFormField(
                  controller: _deviceController,
                  decoration: _inputDecoration('Device ID (from QR) - required'),
                  validator: (v) => _validateNotEmpty(v, 'Device ID'),
                ),
                const SizedBox(height: 10),

                // Email
                TextFormField(
                  controller: _emailController,
                  decoration: _inputDecoration('Email'),
                  keyboardType: TextInputType.emailAddress,
                  validator: _validateEmail,
                ),
                const SizedBox(height: 10),

                // Password
                TextFormField(
                  controller: _passwordController,
                  decoration: _inputDecoration(
                    'Password (≥8, include uppercase, lowercase, number, special char)',
                    isPassword: true,
                    onToggleVisibility: () {
                      setState(() {
                        _obscurePassword = !_obscurePassword;
                      });
                    },
                    obscureText: _obscurePassword,
                  ),
                  obscureText: _obscurePassword,
                  validator: _validatePassword,
                ),
                const SizedBox(height: 10),

                // Confirm password
                TextFormField(
                  controller: _confirmController,
                  decoration: _inputDecoration(
                    'Confirm Password',
                    isPassword: true,
                    onToggleVisibility: () {
                      setState(() {
                        _obscureConfirmPassword = !_obscureConfirmPassword;
                      });
                    },
                    obscureText: _obscureConfirmPassword,
                  ),
                  obscureText: _obscureConfirmPassword,
                  validator: _validateConfirm,
                ),
                const SizedBox(height: 20),

                // Sign Up button
                SizedBox(
                  width: 160,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _attemptSignup,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color.fromARGB(255, 73, 172, 123),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(25),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                        : const Text(
                      'Create Account',
                      style: TextStyle(color: Colors.black, fontSize: 16),
                    ),
                  ),
                ),
                const SizedBox(height: 28),
              ],
            ),
          ),
        ),
      ),
    );
  }
}