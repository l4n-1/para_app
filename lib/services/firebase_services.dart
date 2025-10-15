// lib/services/firebase_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class FirebaseService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<void> saveJeepneyLocation(
      String jeepneyId,
      Map<String, dynamic> data,
      ) async {
    await _db.collection('jeepneys').doc(jeepneyId).set(data, SetOptions(merge: true));
  }

  Stream<DocumentSnapshot> getJeepneyData(String jeepneyId) {
    return _db.collection('jeepneys').doc(jeepneyId).snapshots();
  }

  Future<void> bookRide(
      String routeId,
      Map<String, dynamic> bookingData,
      ) async {
    await _db
        .collection('routes')
        .doc(routeId)
        .collection('bookings')
        .add(bookingData);
  }

  // --- New helper methods for activation / user updates ---

  /// Update the user's role and optionally attach hardwareId & plate number.
  Future<void> updateUserRoleAndHardware({
    required String uid,
    required String role,
    required String hardwareId,
    String? plateNumber,
    String? contactNumber,
  }) async {
    final data = <String, dynamic>{
      'role': role,
      'linkedHardwareId': hardwareId,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (plateNumber != null) data['plateNumber'] = plateNumber;
    if (contactNumber != null) data['contactNumber'] = contactNumber;
    await _db.collection('users').doc(uid).set(data, SetOptions(merge: true));
  }

  /// Create/update user profile fields on signup.
  Future<void> upsertUserProfile({
    required String uid,
    required String firstName,
    required String lastName,
    required String userName,
    required DateTime dob,
    required String contactNumber,
    required String role,
    String? plateNumber,
  }) async {
    final data = {
      'firstName': firstName,
      'lastName': lastName,
      'userName': userName,
      'dob': dob.toIso8601String(),
      'contactNumber': contactNumber,
      'role': role,
      'plateNumber': plateNumber ?? '',
      'createdAt': FieldValue.serverTimestamp(),
    };
    await _db.collection('users').doc(uid).set(data, SetOptions(merge: true));
  }
}