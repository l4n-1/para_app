import 'package:para2/services/snackbar_service.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:para2/pages/home/role_router.dart';
import 'package:para2/pages/login/tsuperhero_signup_page.dart';
import 'package:para2/services/auth_service.dart';
import 'package:para2/pages/home/shared_home.dart';
import 'package:para2/pages/login/login.dart';

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
  final _authService = AuthService();

  bool _isLoading = false;
  Timer? _emailCheckTimer;

  // ✅ ADDED: Show/hide password states
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

  // ✅ FIXED: Better password requirement description
  final RegExp _passwordRegex = RegExp(r'^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[@$!%*?&])[A-Za-z\d@$!%*?&]{8,}$');
  final RegExp _phContactRegex = RegExp(r'^09\d{9}$');
  final RegExp _emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  // Field error states
  String? _emailError;
  String? _contactError;
  String? _passwordError;
  String? _confirmPasswordError;

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

  void _validateField(String fieldName, String value) {
    switch (fieldName) {
      case 'email':
        setState(() {
          _emailError = value.isEmpty ? 'This field is required'
              : !_emailRegex.hasMatch(value) ? 'Enter a valid email' : null;
        });
        break;
      case 'contact':
        setState(() {
          _contactError = value.isEmpty ? 'This field is required'
              : !_phContactRegex.hasMatch(value) ? 'Enter valid PH number (09XXXXXXXXX)' : null;
        });
        break;
      case 'password':
        setState(() {
          _passwordError = value.isEmpty ? 'This field is required'
              : !_passwordRegex.hasMatch(value)
              ? 'For security, password should have at least:\n• 8+ characters\n• 1 uppercase letter\n• 1 lowercase letter\n• 1 number\n• 1 special character'
              : null;
        });
        break;
      case 'confirmPassword':
        setState(() {
          _confirmPasswordError = value.isEmpty ? 'This field is required'
              : value != _passwordController.text ? 'Passwords do not match' : null;
        });
        break;
    }
  }

  Future<void> _signUp() async {
    final email = _emailController.text.trim();
    final contact = _contactController.text.trim();
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;

    // Validate all fields
    _validateField('email', email);
    _validateField('contact', contact);
    _validateField('password', password);
    _validateField('confirmPassword', confirmPassword);

    // Check if any errors exist
    if (_emailError != null || _contactError != null ||
        _passwordError != null || _confirmPasswordError != null) {
      _triggerShake();
      return;
    }

    setState(() => _isLoading = true);

    try {
      final userCredential = await _authService.signUpWithEmail(
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
        'userName': widget.userName,
        'firstName': widget.firstName,
        'lastName': widget.lastName,
      }, SetOptions(merge: true));

      await user.sendEmailVerification();
      _showVerificationDialog(user);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        setState(() => _emailError = 'Email already registered');
      } else if (e.code == 'username-taken') {
        _showSnackBar('Sign up failed: ${e.message}');
      } else {
        _showSnackBar('Sign up failed: ${e.message}');
      }
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
        return AlertDialog(
          title: const Text('Email Verification Sent'),
          content: const Text(
            'A verification email has been sent to your email address. '
                'Please verify your email before signing in.\n\n'
                'You will be redirected to the login page.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginPage()),
                      (route) => false,
                );
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  void _showSnackBar(String message) {
    SnackbarService.show(context, message);
  }

  // ✅ UPDATED: Input decoration with show/hide password toggle
  InputDecoration _inputDecoration(String hintText, String? errorText, {bool isPassword = false, VoidCallback? onToggleVisibility, bool obscureText = true}) {
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
      // ✅ ADDED: Show/hide password button
      suffixIcon: isPassword ? IconButton(
        icon: Icon(
          obscureText ? Icons.visibility_off : Icons.visibility,
          color: Colors.grey[600],
        ),
        onPressed: onToggleVisibility,
      ) : null,
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
                    // Email Field
                    TextField(
                      controller: _emailController,
                      decoration: _inputDecoration('Email', _emailError),
                      onChanged: (value) => _validateField('email', value),
                    ),
                    const SizedBox(height: 10),

                    // Contact Number Field
                    TextField(
                      controller: _contactController,
                      keyboardType: TextInputType.phone,
                      decoration: _inputDecoration('Contact Number (09XXXXXXXXX)', _contactError),
                      onChanged: (value) => _validateField('contact', value),
                    ),
                    const SizedBox(height: 10),

                    // Password Field with show/hide
                    TextField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      decoration: _inputDecoration(
                        'Password',
                        _passwordError,
                        isPassword: true,
                        onToggleVisibility: () {
                          setState(() {
                            _obscurePassword = !_obscurePassword;
                          });
                        },
                        obscureText: _obscurePassword,
                      ),
                      onChanged: (value) => _validateField('password', value),
                    ),
                    const SizedBox(height: 10),

                    // Confirm Password Field with show/hide
                    TextField(
                      controller: _confirmPasswordController,
                      obscureText: _obscureConfirmPassword,
                      decoration: _inputDecoration(
                        'Confirm Password',
                        _confirmPasswordError,
                        isPassword: true,
                        onToggleVisibility: () {
                          setState(() {
                            _obscureConfirmPassword = !_obscureConfirmPassword;
                          });
                        },
                        obscureText: _obscureConfirmPassword,
                      ),
                      onChanged: (value) => _validateField('confirmPassword', value),
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