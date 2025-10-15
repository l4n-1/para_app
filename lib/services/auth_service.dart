import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // 📧 Email/password signup + Firestore profile creation
  Future<UserCredential> signUpWithEmail({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    required String userName,
    required DateTime dob,
  }) async {
    // Create Firebase account
    final userCredential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    // Send email verification
    await userCredential.user!.sendEmailVerification();

    // Save user profile in Firestore
    await _firestore.collection('users').doc(userCredential.user!.uid).set({
      'firstName': firstName,
      'lastName': lastName,
      'userName': userName,
      'dob': dob.toIso8601String(),
      'email': email,
      'role': 'pasahero',
      'createdAt': FieldValue.serverTimestamp(),
    });

    return userCredential;
  }

  // 🔐 Email/password login
  Future<UserCredential> signInWithEmail(String email, String password) async {
    return await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  // 🔵 Google Sign-In (Compatible with google_sign_in: ^7.1.1)
  Future<UserCredential?> signInWithGoogle() async {
    try {
      // ✅ Explicit initialization required in v7+
      await _googleSignIn.initialize();

      // ✅ authenticate() replaces signIn()
      final GoogleSignInAccount? googleUser = await _googleSignIn.authenticate();

      if (googleUser == null) return null; // User cancelled sign-in

      // ✅ In v7, authentication is synchronous
      final GoogleSignInAuthentication googleAuth = googleUser.authentication;

      // ✅ accessToken may no longer exist in v7; only idToken is guaranteed
      final credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
      );

      final userCredential = await _auth.signInWithCredential(credential);
      final user = userCredential.user;
      if (user == null) return null;

      // 🔹 Firestore user reference
      final docRef = _firestore.collection('users').doc(user.uid);
      final snapshot = await docRef.get();

      // 🔹 If new Google user, create Firestore entry
      if (!snapshot.exists) {
        await docRef.set({
          'firstName': googleUser.displayName?.split(' ').first ?? '',
          'lastName': googleUser.displayName?.split(' ').skip(1).join(' ') ?? '',
          'email': googleUser.email,
          'role': 'pasahero',
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      return userCredential;
    } catch (e) {
      debugPrint('❌ Google sign-in failed: $e');
      rethrow;
    }
  }

  // 🚪 Sign out from Firebase and Google
  Future<void> signOut() async {
    await _auth.signOut();
    await _googleSignIn.disconnect();
  }
}