import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_core/firebase_core.dart';

class RealtimeDatabaseService {
  late final FirebaseDatabase _database;

  RealtimeDatabaseService() {
    _database = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL: 'https://paratotype-default-rtdb.asia-southeast1.firebasedatabase.app/',
    );
  }

  FirebaseDatabase get database => _database;

  DatabaseReference getJeepneyGpsRef(String jeepneyId) {
    return _database.ref('devices/$jeepneyId');
  }

  DatabaseReference get devicesRef => _database.ref('devices');

  Future<void> updateGps(String jeepneyId, Map<String, dynamic> data) async {
    await getJeepneyGpsRef(jeepneyId).set(data);
  }

  Stream<DatabaseEvent> listenGps(String jeepneyId) {
    return getJeepneyGpsRef(jeepneyId).onValue;
  }
}