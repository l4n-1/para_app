import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:para2/services/snackbar_service.dart';

class DestinationDisplay extends StatefulWidget {
  final String roleLabel;

  const DestinationDisplay({
    super.key,
    required this.roleLabel,
  });

  @override
  State<DestinationDisplay> createState() => _DestinationDisplayState();
}

class _DestinationDisplayState extends State<DestinationDisplay> {
  String _destination = '';

  @override
  void initState() {
    super.initState();
    _loadDestination();
  }

  Future<void> _loadDestination() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('para_requests')
          .doc(user.uid)
          .get();

      if (doc.exists) {
        final data = doc.data()!;
        final dest = data['destination']?.toString() ?? '';

        if (dest.isNotEmpty) {
          SnackbarService.show(context,
              'Your current destination is: $dest',
              duration: const Duration(seconds: 3));
        } else {
          SnackbarService.show(context,
              'No destination set. Please set your destination in profile settings.',
              duration: const Duration(seconds: 3));
        }

        setState(() {
          _destination = dest;
        });
      }
    } catch (e) {
      debugPrint('Error fetching destination: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          alignment: Alignment.centerLeft,
          child: Text(
            widget.roleLabel == 'TSUPERHERO' ? 'Your Route' : 'Your Destination',
            textAlign: TextAlign.left,
            style: const TextStyle(
              
              height: 2,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 4),
         Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: const Color.fromARGB(255, 80, 79, 85),
                borderRadius: BorderRadius.circular(25),
              ),
              child: Row(
                children: [
                  Image.asset('assets/USERPIN.png', height: 22),
                  const SizedBox(width: 8),
                  Text(
                    widget.roleLabel == 'TSUPERHERO'
                        ? 'not yet implemented'
                        : 'To $_destination',
                    style: const TextStyle(
                      height: 1,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          
      ],
    );
  }
}