import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ✅ FIXED: More flexible password regex - 8+ chars, 1 uppercase, 1 number
  final RegExp _passwordRegex = RegExp(r'^(?=.*[A-Z])(?=.*\d).{8,}$');

  // Check if username exists
  Future<bool> isUsernameTaken(String username) async {
    final query = await _firestore.collection('users')
        .where('userName', isEqualTo: username.trim())
        .limit(1)
        .get();
    return query.docs.isNotEmpty;
  }

  // Check if email exists
  Future<bool> isEmailTaken(String email) async {
    final query = await _firestore.collection('users')
        .where('email', isEqualTo: email.trim().toLowerCase())
        .limit(1)
        .get();
    return query.docs.isNotEmpty;
  }

  // 📧 Email/password signup + Firestore profile creation
  Future<UserCredential> signUpWithEmail({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    required String userName,
    required DateTime dob,
  }) async {
    // ✅ FIXED: Better error message with relaxed requirements
    if (!_passwordRegex.hasMatch(password)) {
      throw FirebaseAuthException(
        code: 'weak-password',
        message: 'Password must be at least 8 characters with 1 uppercase letter and 1 number',
      );
    }

    // Check for duplicates
    if (await isUsernameTaken(userName)) {
      throw FirebaseAuthException(
        code: 'username-taken',
        message: 'Username already exists',
      );
    }

    if (await isEmailTaken(email)) {
      throw FirebaseAuthException(
        code: 'email-already-in-use',
        message: 'Email already registered',
      );
    }

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
      'email': email.toLowerCase(),
      'role': 'pasahero',
      'points': 0,
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

  // 🔵 Google Sign-In
  Future<UserCredential?> signInWithGoogle() async {
    try {
      final GoogleSignIn googleSignIn = GoogleSignIn();
      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();

      if (googleUser == null) return null;

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final UserCredential userCredential = await _auth.signInWithCredential(credential);
      final User? user = userCredential.user;

      if (user == null) return null;

      // Create user profile if it doesn't exist
      final userDoc = _firestore.collection('users').doc(user.uid);
      final userSnapshot = await userDoc.get();

      if (!userSnapshot.exists) {
        final nameParts = user.displayName?.split(' ') ?? ['Google', 'User'];
        final firstName = nameParts.first;
        final lastName = nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '';

        await userDoc.set({
          'firstName': firstName,
          'lastName': lastName,
          'email': user.email,
          'role': 'pasahero',
          'points': 0,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      return userCredential;
    } catch (e) {
      debugPrint('❌ Google sign-in failed: $e');
      rethrow;
    }
  }

  // 🚪 Sign out from Firebase
  Future<void> signOut() async {
    await _auth.signOut();
    await GoogleSignIn().signOut();
  }

  // Add user points
  Future<void> addUserPoints(String userId, int points) async {
    await _firestore.collection('users').doc(userId).update({
      'points': FieldValue.increment(points),
      'lastPointsUpdate': FieldValue.serverTimestamp(),
    });
  }

  // Redeem points
  Future<void> redeemPoints(String userId, int points) async {
    await _firestore.collection('users').doc(userId).update({
      'points': FieldValue.increment(-points),
    });
  }

  // Get user points
  Future<int> getUserPoints(String userId) async {
    try {
      final doc = await _firestore.collection('users').doc(userId).get();
      return (doc.data()?['points'] as int?) ?? 0;
    } catch (e) {
      debugPrint('Error getting user points: $e');
      return 0;
    }
  }
}