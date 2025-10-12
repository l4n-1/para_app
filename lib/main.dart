// lib/main.dart
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:para2/pages/login.dart';
import 'package:para2/pages/pasahero_home.dart';
import 'package:para2/pages/tsuperhero_home.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  Future<Widget> _decideStartPage() async {
    final auth = FirebaseAuth.instance;
    final firestore = FirebaseFirestore.instance;
    final user = auth.currentUser;

    // Not logged in → go to login
    if (user == null) return const LoginPage();

    // Logged in but email not verified → back to login
    await user.reload();
    if (!user.emailVerified) return const LoginPage();

    // Logged in + verified → check role
    try {
      final doc = await firestore.collection('users').doc(user.uid).get();
      if (!doc.exists) return const LoginPage();

      final data = doc.data()!;
      final role = (data['role'] ?? 'pasahero').toString().toLowerCase();
      if (role == 'tsuperhero') return const TsuperheroHome();
      return const PasaheroHome();
    } catch (e) {
      debugPrint('Error loading role: $e');
      return const LoginPage();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PARA!',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.blue,
      ),
      home: FutureBuilder<Widget>(
        future: _decideStartPage(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            // Splash / loading
            return const Scaffold(
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Image(
                      image: AssetImage('assets/Paralogotemp.png'),
                      height: 120,
                    ),
                    SizedBox(height: 20),
                    CircularProgressIndicator(),
                  ],
                ),
              ),
            );
          }
          if (snapshot.hasError) {
            return Scaffold(
              body: Center(
                child: Text('Error: ${snapshot.error}'),
              ),
            );
          }
          return snapshot.data!;
        },
      ),
    );
  }
}