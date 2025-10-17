import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_core/firebase_core.dart';

class RealtimeDatabaseService {
  final FirebaseDatabase _database = FirebaseDatabase.instanceFor(
    app: Firebase.app(),
    databaseURL:
        'https://paratotype-default-rtdb.asia-southeast1.firebasedatabase.app/',
  );

  /// ✅ Public getter so other files can use the configured database instance
  FirebaseDatabase get database => _database;

  /// Optional convenience method (you can still keep or remove gps_data path)
  DatabaseReference getJeepneyGpsRef(String jeepneyId) {
    return _database.ref('devices/$jeepneyId');
  }

  Future<void> updateGps(String jeepneyId, Map<String, dynamic> data) async {
    await getJeepneyGpsRef(jeepneyId).set(data);
  }

  Stream<DatabaseEvent> listenGps(String jeepneyId) {
    return getJeepneyGpsRef(jeepneyId).onValue;
  }
}
