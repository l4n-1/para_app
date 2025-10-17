// lib/pages/login/signup_step2.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:para2/pages/home/role_router.dart';
import 'package:para2/pages/login/tsuperhero_signup_page.dart';
import 'package:para2/services/auth_service.dart';
import 'package:para2/pages/home/shared_home.dart';

class SignupStep2 extends StatefulWidget {
  final String firstName;
  final String lastName;
  final String userName;
  final DateTime dob;

  const SignupStep2({
    super.key,
    required this.firstName,
    required this.lastName,
    required this.userName,
    required this.dob,
  });

  @override
  State<SignupStep2> createState() => _SignupStep2State();
}

class _SignupStep2State extends State<SignupStep2>
    with SingleTickerProviderStateMixin {
  final _emailController = TextEditingController();
  final _contactController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _firestore = FirebaseFirestore.instance;

  bool _isLoading = false;
  Timer? _emailCheckTimer;

  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

  final RegExp _passwordRegex = RegExp(r'^(?=.*[A-Z])(?=.*\d).{8,}$');
  final RegExp _phContactRegex = RegExp(r'^09\d{9}$');

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _shakeAnimation = Tween<double>(
      begin: 0,
      end: 10,
    ).chain(CurveTween(curve: Curves.elasticIn)).animate(_shakeController);
  }

  @override
  void dispose() {
    _emailCheckTimer?.cancel();
    _shakeController.dispose();
    _emailController.dispose();
    _contactController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _triggerShake() {
    _shakeController.forward(from: 0);
  }

  Future<void> _signUp() async {
    final email = _emailController.text.trim();
    final contact = _contactController.text.trim();
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;

    if (email.isEmpty ||
        contact.isEmpty ||
        password.isEmpty ||
        confirmPassword.isEmpty) {
      _showSnackBar('Please fill in all fields');
      _triggerShake();
      return;
    }

    if (!_phContactRegex.hasMatch(contact)) {
      _showSnackBar(
        'Please enter a valid Philippine contact number (09XXXXXXXXX).',
      );
      _triggerShake();
      return;
    }

    if (password != confirmPassword) {
      _showSnackBar('Passwords do not match');
      _triggerShake();
      return;
    }

    if (!_passwordRegex.hasMatch(password)) {
      _showSnackBar(
        'Password must be at least 8 chars, with 1 uppercase and 1 number.',
      );
      _triggerShake();
      return;
    }

    setState(() => _isLoading = true);

    try {
      final userCredential = await AuthService().signUpWithEmail(
        email: email,
        password: password,
        firstName: widget.firstName,
        lastName: widget.lastName,
        userName: widget.userName,
        dob: widget.dob,
      );

      final user = userCredential.user!;
      await _firestore.collection('users').doc(user.uid).set({
        'role': widget is TsuperheroSignupPage ? 'tsuperhero' : 'pasahero',
        'contact': contact,
        'email': email,
      }, SetOptions(merge: true));

      await user.sendEmailVerification();
      _showVerificationDialog(user);
    } on FirebaseAuthException catch (e) {
      _showSnackBar('Sign up failed: ${e.message}');
      _triggerShake();
    } catch (e) {
      _showSnackBar('Sign up failed: $e');
      _triggerShake();
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showVerificationDialog(User user) {
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.6),
      builder: (_) {
        _emailCheckTimer = Timer.periodic(const Duration(seconds: 3), (
          _,
        ) async {
          await user.reload();
          final refreshedUser = FirebaseAuth.instance.currentUser;

          if (refreshedUser != null && refreshedUser.emailVerified) {
            _emailCheckTimer?.cancel();
            if (mounted) Navigator.of(context).pop();

            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const RoleRouter()),
            );
          }
        });

        return Center(
          child: Container(
            padding: const EdgeInsets.all(30),
            width: 250,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 10,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(
                  color: Color.fromARGB(255, 73, 172, 123),
                ),
                SizedBox(height: 20),
                Text(
                  "Verifying...\nCheck your email.",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  InputDecoration _inputDecoration(String hintText) {
    return InputDecoration(
      hintText: hintText,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(25),
        borderSide: BorderSide.none,
      ),
      filled: true,
      fillColor: Colors.grey[200],
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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
              const SizedBox(height: 40),
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back),
                ),
              ),
              const SizedBox(height: 20),
              Image.asset('assets/Paralogotemp.png', height: 150, width: 150),
              const SizedBox(height: 40),

              // Animated wrapper for email field
              AnimatedBuilder(
                animation: _shakeAnimation,
                builder: (context, child) {
                  return Transform.translate(
                    offset: Offset(_shakeAnimation.value, 0),
                    child: child,
                  );
                },
                child: Column(
                  children: [
                    TextField(
                      controller: _emailController,
                      decoration: _inputDecoration('Email'),
                    ),
                    const SizedBox(height: 10),

                    // Contact Number
                    TextField(
                      controller: _contactController,
                      keyboardType: TextInputType.phone,
                      decoration: _inputDecoration(
                        'Contact Number (09XXXXXXXXX)',
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Password
                    TextField(
                      controller: _passwordController,
                      obscureText: true,
                      decoration: _inputDecoration('Password'),
                    ),
                    const SizedBox(height: 10),

                    // Confirm Password
                    TextField(
                      controller: _confirmPasswordController,
                      obscureText: true,
                      decoration: _inputDecoration('Confirm Password'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),

              // Sign Up Button
              SizedBox(
                width: 150,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _signUp,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color.fromARGB(255, 73, 172, 123),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(25),
                    ),
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                          'Sign Up',
                          style: TextStyle(color: Colors.black, fontSize: 16),
                        ),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}
