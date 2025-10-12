// lib/pages/login.dart
import 'package:flutter/material.dart';
import 'package:para2/pages/rolepick.dart';
import 'package:para2/pages/signup_page.dart';
import 'package:para2/services/auth_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:para2/pages/pasahero_home.dart';
import 'package:para2/pages/tsuperhero_home.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final AuthService _authService = AuthService();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _autoRedirectIfLoggedIn();
  }

  Future<void> _autoRedirectIfLoggedIn() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await user.reload();
      final current = FirebaseAuth.instance.currentUser;
      if (current != null && current.emailVerified) {
        // fetch role
        final role = await _fetchRole(current.uid);
        _navigateByRole(role);
      }
    }
  }

  Future<String?> _fetchRole(String uid) async {
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (doc.exists) {
        final data = doc.data();
        return data != null && data.containsKey('role') ? data['role'] as String? : null;
      }
    } catch (e) {
      // ignore - fallback handled by caller
    }
    return null;
  }

  Future<void> _loginWithEmail() async {
    setState(() => _isLoading = true);
    try {
      final userCredential = await _authService.signInWithEmail(
        _emailController.text.trim(),
        _passwordController.text.trim(),
      );

      final user = userCredential.user;
      if (user == null) throw FirebaseAuthException(code: 'NO_USER', message: 'No user returned');

      await user.reload();
      if (!user.emailVerified) {
        await user.sendEmailVerification();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please verify your email before signing in. Verification email sent.'),
          ),
        );
        await _authService.signOut();
      } else {
        final role = await _fetchRole(user.uid) ?? 'pasahero';
        _navigateByRole(role);
      }
    } on FirebaseAuthException catch (e) {
      _showErrorSnackBar('Login failed: ${e.message}');
    } catch (e) {
      _showErrorSnackBar('Login failed: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loginWithGoogle() async {
    setState(() => _isLoading = true);
    try {
      final userCredential = await _authService.signInWithGoogle();
      final user = userCredential?.user;
      if (user != null) {
        await user.reload();
        if (!user.emailVerified) {
          // Google sign-ins often already verified; but handle just in case
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please verify your account (if required).')),
          );
        }
        final role = await _fetchRole(user.uid) ?? 'pasahero';
        _navigateByRole(role);
      }
    } catch (e) {
      _showErrorSnackBar('Google Sign-In failed: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _navigateByRole(String? role) {
    // default to pasahero
    final r = (role ?? 'pasahero').toLowerCase();
    if (r == 'tsuperhero') {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const TsuperheroHome()),
      );
    } else if (r == 'pasahero') {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const PasaheroHome()),
      );
    } else {
      // If role unknown, fallback to RolePick (or pasahero)
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const RolePick()),
      );
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  InputDecoration _inputDecoration(String hintText) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: TextStyle(
        color: Colors.black.withOpacity(0.5),
        fontFamily: 'HelveticaNowTextBold',
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(25.0),
        borderSide: BorderSide.none,
      ),
      filled: true,
      fillColor: Colors.grey[200],
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 20,
        vertical: 16,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 233, 233, 231),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 100.0),
              Image.asset(
                'assets/Paralogotemp.png',
                height: 200.0,
                width: 200.0,
              ),
              const SizedBox(height: 100.0),

              // Email Field
              TextField(
                controller: _emailController,
                decoration: _inputDecoration('email/username'),
              ),
              const SizedBox(height: 20.0),

              // Password Field
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: _inputDecoration('password'),
              ),
              const SizedBox(height: 30.0),

              // Sign In Button
              SizedBox(
                width: 120,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _loginWithEmail,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color.fromARGB(255, 73, 172, 123),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(25.0),
                    ),
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                    'Sign In',
                    style: TextStyle(color: Colors.black, fontSize: 16),
                  ),
                ),
              ),
              const SizedBox(height: 10.0),

              // OR Divider
              Row(
                children: [
                  Expanded(
                    child: Divider(color: Colors.grey[400], thickness: 1.0),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10.0),
                    child: Text('OR', style: TextStyle(color: Colors.grey)),
                  ),
                  Expanded(
                    child: Divider(color: Colors.grey[400], thickness: 1.0),
                  ),
                ],
              ),
              const SizedBox(height: 10.0),

              // Google Sign-In
              SizedBox(
                width: 235,
                child: OutlinedButton(
                  onPressed: _isLoading ? null : _loginWithGoogle,
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30.0),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 16.0),
                    side: const BorderSide(color: Colors.grey),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Image.asset(
                        'assets/android_light_rd_na@3x.png',
                        height: 30,
                        width: 30,
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'Sign in with Google',
                        style: TextStyle(color: Colors.black, fontSize: 16),
                      ),
                    ],
                  ),
                ),
              ),

              // Sign up link
              Padding(
                padding: const EdgeInsets.only(top: 20.0),
                child: GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const SignupPage(),
                      ),
                    );
                  },
                  child: const Text(
                    "Don't have an account yet? Sign up",
                    style: TextStyle(
                      color: Colors.blue,
                      fontSize: 14,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 40.0),

              // PARA! Text
              Padding(
                padding: const EdgeInsets.only(bottom: 20.0),
                child: Text(
                  'PARA!',
                  style: TextStyle(
                    color: Colors.black.withOpacity(0.35),
                    fontSize: 16.0,
                    fontFamily: 'HelveticaNowTextBold',
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