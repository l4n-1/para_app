// lib/pages/login.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:para2/pages/home/role_router.dart';
import 'package:para2/services/auth_service.dart';
import 'package:para2/services/snackbar_service.dart';
import 'package:para2/pages/login/signup_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with SingleTickerProviderStateMixin {
  final _emailOrUsernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();
  bool _isLoading = false;

  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

  final RegExp _passwordRegex = RegExp(r'^(?=.*[A-Z])(?=.*\d).{8,}$');

  @override
  void initState() {
    super.initState();

    // Initialize the shake animation controller
    _shakeController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _shakeAnimation = Tween<double>(begin: 0, end: 10)
        .chain(CurveTween(curve: Curves.elasticIn))
        .animate(_shakeController);

    _autoRedirectIfLoggedIn();
  }

  @override
  void dispose() {
    _shakeController.dispose();
    _emailOrUsernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _autoRedirectIfLoggedIn() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await user.reload();
      final current = FirebaseAuth.instance.currentUser;
      if (current != null && current.emailVerified) {
        final role = await _fetchRole(current.uid);
        _navigateByRole(role);
      }
    }
  }

  Future<String?> _fetchRole(String uid) async {
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (doc.exists) {
        return (doc.data()?['role'] as String?) ?? 'pasahero';
      }
    } catch (_) {}
    return 'pasahero';
  }

  /// Looks up Firestore to see if this string is a username and returns its email
  Future<String?> _lookupEmailByUsername(String input) async {
    try {
      final query = await FirebaseFirestore.instance
          .collection('users')
          .where('userName', isEqualTo: input.trim())
          .limit(1)
          .get();

      if (query.docs.isNotEmpty) {
        return query.docs.first['email'];
      }
    } catch (_) {}
    return null;
  }

  Future<void> _loginWithEmailOrUsername() async {
    final input = _emailOrUsernameController.text.trim();
    final password = _passwordController.text.trim();

    if (input.isEmpty || password.isEmpty) {
      _showSnackBar('Please enter both fields.');
      _triggerShake();
      return;
    }

    if (!_passwordRegex.hasMatch(password)) {
      _showSnackBar('Password must have at least 8 chars, 1 uppercase, and 1 number.');
    }

    setState(() => _isLoading = true);

    try {
      String loginEmail = input;

      // If input doesn’t contain '@', assume it’s a username and look up email
      if (!input.contains('@')) {
        final foundEmail = await _lookupEmailByUsername(input);
        if (foundEmail == null) {
          _showSnackBar('No account found with username "$input".');
          _triggerShake();
          setState(() => _isLoading = false);
          return;
        }
        loginEmail = foundEmail;
      }

      final userCredential = await _authService.signInWithEmail(loginEmail, password);
      final user = userCredential.user;

      if (user == null) {
        throw FirebaseAuthException(code: 'NO_USER', message: 'No user returned.');
      }

      await user.reload();
      if (!user.emailVerified) {
        await user.sendEmailVerification();
        _showSnackBar(
          'Please verify your email before signing in. Verification link sent.',
        );
        await _authService.signOut();
      } else {
        final role = await _fetchRole(user.uid);
        _navigateByRole(role);
      }
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found') {
        _showSnackBar('No account found for that email.');
        _triggerShake();
      } else if (e.code == 'wrong-password') {
        _showSnackBar('Incorrect password. Please try again.');
        _triggerShake();
      } else {
        _showSnackBar('Login failed: ${e.message}');
      }
    } catch (e) {
      _showSnackBar('Login failed: $e');
      _triggerShake();
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _triggerShake() {
    _shakeController.forward(from: 0);
  }

  Future<void> _loginWithGoogle() async {
    setState(() => _isLoading = true);
    try {
      final userCredential = await _authService.signInWithGoogle();
      final user = userCredential?.user;
      if (user != null) {
        await user.reload();
        final role = await _fetchRole(user.uid);
        _navigateByRole(role);
      }
    } catch (e) {
      _showSnackBar('Google Sign-In failed: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // ✅ Clean navigation — SharedHome handles displaying the correct page
  void _navigateByRole(String? role) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const RoleRouter()),
    );
  }

  void _showSnackBar(String message) {
    SnackbarService.show(context, message);
  }

  InputDecoration _inputDecoration(String hintText) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: TextStyle(
        color: Colors.black.withOpacity(0.5),
        fontFamily: 'HelveticaNowTextBold',
      ),
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
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 100),
              Image.asset('assets/Paralogotemp.png', height: 200, width: 200),
              const SizedBox(height: 100),

              // Animated Email/Username Field (Shake effect)
              AnimatedBuilder(
                animation: _shakeAnimation,
                builder: (context, child) {
                  return Transform.translate(
                    offset: Offset(_shakeAnimation.value, 0),
                    child: child,
                  );
                },
                child: TextField(
                  controller: _emailOrUsernameController,
                  decoration: _inputDecoration('Email or Username'),
                ),
              ),
              const SizedBox(height: 20),

              // Password Field
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: _inputDecoration('Password'),
              ),
              const SizedBox(height: 30),

              // Sign In Button
              SizedBox(
                width: 120,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _loginWithEmailOrUsername,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color.fromARGB(255, 73, 172, 123),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(25),
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
              const SizedBox(height: 10),

              // OR Divider
              Row(
                children: [
                  Expanded(child: Divider(color: Colors.grey[400], thickness: 1)),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10),
                    child: Text('OR', style: TextStyle(color: Colors.grey)),
                  ),
                  Expanded(child: Divider(color: Colors.grey[400], thickness: 1)),
                ],
              ),
              const SizedBox(height: 10),

              // Google Sign-In
              SizedBox(
                width: 235,
                child: OutlinedButton(
                  onPressed: _isLoading ? null : _loginWithGoogle,
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 16),
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
                padding: const EdgeInsets.only(top: 20),
                child: GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SignupPage()),
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
              const SizedBox(height: 40),

              // PARA! Text
              Text(
                'PARA!',
                style: TextStyle(
                  color: Colors.black.withOpacity(0.35),
                  fontSize: 16,
                  fontFamily: 'HelveticaNowTextBold',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}