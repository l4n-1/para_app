import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Email/password signup + store user profile
  Future<UserCredential> signUpWithEmail({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    required String userName,
    required DateTime dob,
  }) async {
    // Create account
    final userCredential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    // Send email verification
    await userCredential.user!.sendEmailVerification();

    // Store extra user info in Firestore
    await _firestore.collection('users').doc(userCredential.user!.uid).set({
      'firstName': firstName,
      'lastName': lastName,
      'userName': userName ?? '',
      'dob': dob.toIso8601String(),
      'email': email,
      'createdAt': FieldValue.serverTimestamp(),
      'role': 'pasahero',
    });

    return userCredential;
  }

  // Email/password login
  Future<UserCredential> signInWithEmail(String email, String password) async {
    return await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  // Google login

  Future<UserCredential?> signInWithGoogle() async {
    _googleSignIn.initialize(
      serverClientId:
          '706884296191-nkuh9soeqn8rhobl7mtt8d5ga7p771kc.apps.googleusercontent.com',
    );
    final GoogleSignInAccount? googleUser = await _googleSignIn.authenticate();

    if (googleUser == null) return null;

    final googlekey = googleUser.authentication;

    final GoogleSignInAuthentication googleAuth =
        await googleUser.authentication;

    final credential = GoogleAuthProvider.credential(
      idToken: googleAuth.idToken,
    );

    final userCredential = await _auth.signInWithCredential(credential);

    // Store Google user info in Firestore if new
    final doc = await _firestore
        .collection('users')
        .doc(userCredential.user!.uid)
        .get();
    if (!doc.exists) {
      await _firestore.collection('users').doc(userCredential.user!.uid).set({
        'firstName': googleUser.displayName?.split(' ').first ?? '',
        'lastName': googleUser.displayName!.split(' ').length > 1
            ? googleUser.displayName!.split(' ').last
            : '',
        'userName': '',
        'dob': '',
        'email': googleUser.email,
        'createdAt': FieldValue.serverTimestamp(),
        'role': 'pasahero',
      });
    }

    return userCredential;
  }

  // Sign out
  Future<void> signOut() async {
    await _auth.signOut();
    await _googleSignIn.signOut();
  }
}
