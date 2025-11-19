import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:para2/pages/login/login.dart';
import 'package:para2/pages/home/pasa/pasahero_home.dart';
import "package:para2/pages/home/tsuper/tsuperhero_home.dart";
import 'package:para2/theme/app_icons.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppIcons.loadIcons(); // ✅ Ensure icons are loaded before app starts
  await Firebase.initializeApp();
  // Enable edge-to-edge mode so app content can extend
  // behind the status and navigation bars (full-screen look).
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarContrastEnforced: false,
  ));
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  Future<Widget> _decideStartPage() async {
    final auth = FirebaseAuth.instance;
    final firestore = FirebaseFirestore.instance;
    final user = auth.currentUser;

    FirebaseAuth.instance.authStateChanges().listen((User? user) {
      if (user == null) {
        debugPrint('User signed out or deleted, returning to login.');
      }
    });

    // Not logged in → go to login
    if (user == null) return const LoginPage();

    try {
      // Reload to make sure user still exists in Firebase
      await user.reload();
      final refreshedUser = auth.currentUser;

      // If user was deleted or null after reload → log out and redirect
      if (refreshedUser == null) {
        await auth.signOut();
        return const LoginPage();
      }

      if (!refreshedUser.emailVerified) return const LoginPage();

      // Check Firestore document for role
      final doc = await firestore
          .collection('users')
          .doc(refreshedUser.uid)
          .get();
      if (!doc.exists) {
        await auth.signOut();
        return const LoginPage();
      }

      final data = doc.data()!;
      final role = (data['role'] ?? 'pasahero').toString().toLowerCase();
      if (role == 'tsuperhero') return const TsuperheroHome();
      return const PasaheroHome();
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found' || e.code == 'invalid-user-token') {
        // Handle the case where the user no longer exists
        await auth.signOut();
        return const LoginPage();
      }
      debugPrint('FirebaseAuth error: ${e.message}');
      return const LoginPage();
    } catch (e) {
      debugPrint('Error loading role: $e');
      await auth.signOut();
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
        listTileTheme: ListTileThemeData(
          titleTextStyle: GoogleFonts.inter(
            fontSize: 15,
            color: Colors.white),
          iconColor:  const Color.fromARGB(255, 171, 236, 66),
        ),
        // ✅ ADDED: Better input field styling
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.grey[200],
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(25),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        ),
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
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error, size: 50, color: Colors.red),
                    const SizedBox(height: 16),
                    Text('Error: ${snapshot.error}'),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: () => runApp(const MyApp()),
                      child: const Text('Restart App'),
                    ),
                  ],
                ),
              ),
            );
          }
          return snapshot.data!;
        },
      ),
    );
  }
}