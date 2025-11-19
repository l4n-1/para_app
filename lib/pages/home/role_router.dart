import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:para2/pages/home/pasa/pasahero_home.dart';
import 'package:para2/pages/home/tsuper/tsuperhero_home.dart';
import 'package:para2/pages/login/login.dart';

class RoleRouter extends StatelessWidget {
  const RoleRouter({super.key});

  Future<Widget> _determineHome() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const LoginPage();

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    final data = doc.data();
    final role = (data?['role'] ?? 'pasahero').toString().toLowerCase();

    if (role == 'tsuperhero') {
      return const TsuperheroHome();
    } else {
      return const PasaheroHome();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Widget>(
      future: _determineHome(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return const Scaffold(
            body: Center(child: Text('Error loading role')),
          );
        }
        return snapshot.data!;
      },
    );
  }
}
