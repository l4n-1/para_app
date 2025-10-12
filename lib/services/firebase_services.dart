import 'package:cloud_firestore/cloud_firestore.dart';

class FirebaseService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<void> saveJeepneyLocation(
    String jeepneyId,
    Map<String, dynamic> data,
  ) async {
    await _db.collection('jeepneys').doc(jeepneyId).set(data);
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
}
