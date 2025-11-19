// lib/services/qr_boarding_service.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:para2/services/RealtimeDatabaseService.dart';
import 'dart:math' as math;
import 'package:google_maps_flutter/google_maps_flutter.dart';

class QRBoardingService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final RealtimeDatabaseService _rtdbService = RealtimeDatabaseService();

  // ✅ GENERATE UNIQUE QR CODE FOR PASSENGER
  Future<Map<String, dynamic>> generatePassengerQR(String passengerId) async {
    try {
      final passengerDoc = await _firestore.collection('users').doc(passengerId).get();
      if (!passengerDoc.exists) {
        throw Exception('Passenger not found');
      }

      final passengerData = passengerDoc.data()!;
      final qrId = 'QR_${DateTime.now().millisecondsSinceEpoch}_${passengerId.substring(0, 8)}';

      // Create QR data with passenger info and session
      final qrData = {
        'qrId': qrId,
        'passengerId': passengerId,
        'passengerName': '${passengerData['firstName']} ${passengerData['lastName']}',
        'passengerContact': passengerData['contact'] ?? '',
        'timestamp': FieldValue.serverTimestamp(),
        'type': 'boarding_pass',
        'status': 'active',
        'expiresAt': FieldValue.serverTimestamp(), // 10-minute expiry
      };

      // Store QR session in Firestore
      await _firestore.collection('qr_sessions').doc(qrId).set(qrData);

      return {
        'success': true,
        'qrId': qrId,
        'qrData': qrData,
        'message': 'QR code generated successfully'
      };
    } catch (e) {
      return {'success': false, 'message': 'QR generation failed: $e'};
    }
  }

  // ✅ PROCESS QR SCAN BY DRIVER (REAL IMPLEMENTATION)
  Future<Map<String, dynamic>> processQRBoarding(
      String scannedQRData,
      String jeepneyId,
      String driverId
      ) async {
    try {
      // Parse QR data (this would be JSON in real QR)
      final qrId = scannedQRData; // In production, parse from JSON

      // Validate QR session
      final qrSession = await _firestore.collection('qr_sessions').doc(qrId).get();
      if (!qrSession.exists) {
        return {'success': false, 'message': '❌ Invalid QR code'};
      }

      final sessionData = qrSession.data()!;
      final passengerId = sessionData['passengerId'];
      final passengerName = sessionData['passengerName'];

      // Check if QR is expired (10-minute window)
      final timestamp = sessionData['timestamp'] as Timestamp;
      final expiryTime = timestamp.toDate().add(const Duration(minutes: 10));
      if (DateTime.now().isAfter(expiryTime)) {
        return {'success': false, 'message': '❌ QR code expired'};
      }

      // Check if already used
      if (sessionData['status'] == 'used') {
        return {'success': false, 'message': '❌ QR code already used'};
      }

      // ✅ GET PASSENGER DETAILS FOR BIYAHE LOGS
      final passengerDoc = await _firestore.collection('users').doc(passengerId).get();
      if (!passengerDoc.exists) {
        return {'success': false, 'message': '❌ Passenger not found'};
      }

      final passengerData = passengerDoc.data()!;

      // ✅ BARYABOX INTEGRATION: Update passenger count
      final trackerRef = _rtdbService.getJeepneyGpsRef(jeepneyId);
      final snapshot = await trackerRef.get();

      if (!snapshot.exists) {
        return {'success': false, 'message': '❌ Jeepney not found in system'};
      }

      final currentData = snapshot.value as Map<dynamic, dynamic>;
      final currentPassengers = (currentData['currentPassengers'] as int?) ?? 0;
      final maxCapacity = (currentData['maxCapacity'] as int?) ?? 20;

      // Check capacity
      if (currentPassengers >= maxCapacity) {
        return {'success': false, 'message': '❌ Jeepney is full! Cannot board.'};
      }

      // ✅ UPDATE BARYABOX PASSENGER COUNT
      await trackerRef.update({
        'currentPassengers': currentPassengers + 1,
        'hasAvailableSeats': (currentPassengers + 1) < maxCapacity,
        'lastBoarding': ServerValue.timestamp,
      });

      // ✅ MARK QR AS USED
      await _firestore.collection('qr_sessions').doc(qrId).update({
        'status': 'used',
        'usedAt': FieldValue.serverTimestamp(),
        'jeepneyId': jeepneyId,
        'driverId': driverId,
      });

      // ✅ CREATE BIYAHE LOG ENTRY
      final logId = 'LOG_${DateTime.now().millisecondsSinceEpoch}';
      final boardingLog = {
        'logId': logId,
        'type': 'boarding',
        'passengerId': passengerId,
        'passengerName': passengerName,
        'passengerContact': passengerData['contact'] ?? '',
        'driverId': driverId,
        'jeepneyId': jeepneyId,
        'action': 'boarded',
        'timestamp': FieldValue.serverTimestamp(),
        'location': currentData.containsKey('latitude') && currentData.containsKey('longitude')
            ? GeoPoint(
          (currentData['latitude'] as num).toDouble(),
          (currentData['longitude'] as num).toDouble(),
        )
            : null,
        'passengerCount': currentPassengers + 1,
        'paymentStatus': 'pending',
        'fareAmount': 15.00, // Base fare
      };

      await _firestore.collection('biyahe_logs').doc(logId).set(boardingLog);

      // ✅ UPDATE PASSENGER'S RIDE HISTORY
      await _firestore.collection('users').doc(passengerId).update({
        'rideHistory': FieldValue.arrayUnion([logId]),
        'lastRide': FieldValue.serverTimestamp(),
        'totalRides': FieldValue.increment(1),
      });

      // ✅ UPDATE DRIVER'S TRIP HISTORY
      await _firestore.collection('users').doc(driverId).update({
        'passengerHistory': FieldValue.arrayUnion([passengerId]),
        'tripsCompleted': FieldValue.increment(1),
        'lastTrip': FieldValue.serverTimestamp(),
      });

      return {
        'success': true,
        'message': '✅ $passengerName successfully boarded!',
        'passengerName': passengerName,
        'passengerId': passengerId,
        'newPassengerCount': currentPassengers + 1,
        'logId': logId,
      };

    } catch (e) {
      debugPrint('QR Boarding Error: $e');
      return {'success': false, 'message': '❌ Boarding failed: $e'};
    }
  }

  // ✅ COMPLETE RIDE & CREATE DROPOFF LOG
  Future<Map<String, dynamic>> completeRideWithDropoff({
    required String passengerId,
    required String jeepneyId,
    required String driverId,
    required String logId,
    required bool paymentCompleted,
    required String paymentMethod, // 'cash', 'coins', 'digital'
    required double fareAmount,
  }) async {
    try {
      final trackerRef = _rtdbService.getJeepneyGpsRef(jeepneyId);
      final snapshot = await trackerRef.get();

      if (snapshot.exists) {
        final currentData = snapshot.value as Map<dynamic, dynamic>;
        final currentPassengers = (currentData['currentPassengers'] as int?) ?? 1;

        // ✅ UPDATE BARYABOX - DECREMENT PASSENGER COUNT
        await trackerRef.update({
          'currentPassengers': currentPassengers - 1,
          'hasAvailableSeats': true,
          'lastUpdate': ServerValue.timestamp,
        });

        // ✅ CREATE DROPOFF LOG ENTRY
        final dropoffLogId = 'DROP_${DateTime.now().millisecondsSinceEpoch}';
        final dropoffLog = {
          'logId': dropoffLogId,
          'type': 'dropoff',
          'passengerId': passengerId,
          'driverId': driverId,
          'jeepneyId': jeepneyId,
          'originalLogId': logId,
          'action': 'dropped_off',
          'timestamp': FieldValue.serverTimestamp(),
          'location': currentData.containsKey('latitude') && currentData.containsKey('longitude')
              ? GeoPoint(
            (currentData['latitude'] as num).toDouble(),
            (currentData['longitude'] as num).toDouble(),
          )
              : null,
          'paymentStatus': paymentCompleted ? 'completed' : 'pending',
          'paymentMethod': paymentMethod,
          'fareAmount': fareAmount,
          'passengerCount': currentPassengers - 1,
        };

        await _firestore.collection('biyahe_logs').doc(dropoffLogId).set(dropoffLog);

        // ✅ UPDATE ORIGINAL BOARDING LOG
        await _firestore.collection('biyahe_logs').doc(logId).update({
          'dropoffLogId': dropoffLogId,
          'rideStatus': 'completed',
          'paymentStatus': paymentCompleted ? 'completed' : 'pending',
          'paymentMethod': paymentMethod,
          'fareAmount': fareAmount,
        });

        return {
          'success': true,
          'message': '✅ Ride completed successfully',
          'dropoffLogId': dropoffLogId,
          'newPassengerCount': currentPassengers - 1,
        };
      }

      return {'success': false, 'message': 'Jeepney not found in system'};
    } catch (e) {
      return {'success': false, 'message': 'Error completing ride: $e'};
    }
  }

  // ✅ GET BIYAHE LOGS FOR USER
  Stream<QuerySnapshot> getUserBiyaheLogs(String userId, {String userType = 'passenger'}) {
    final field = userType == 'passenger' ? 'passengerId' : 'driverId';
    return _firestore
        .collection('biyahe_logs')
        .where(field, isEqualTo: userId)
        .orderBy('timestamp', descending: true)
        .limit(50)
        .snapshots();
  }

  // ✅ GET SPECIFIC BIYAHE LOG DETAILS
  Future<DocumentSnapshot> getBiyaheLogDetails(String logId) {
    return _firestore.collection('biyahe_logs').doc(logId).get();
  }

  // ✅ REPORT SYSTEM - Report user for violations
  Future<Map<String, dynamic>> submitReport({
    required String reporterId,
    required String reportedUserId,
    required String reportType, // 'harassment', 'non_payment', 'reckless_driving', etc.
    required String description,
    required String logId, // Associated biyahe log
    required List<String> evidenceUrls, // Photo URLs
  }) async {
    try {
      final reportId = 'REPORT_${DateTime.now().millisecondsSinceEpoch}';

      final reportData = {
        'reportId': reportId,
        'reporterId': reporterId,
        'reportedUserId': reportedUserId,
        'reportType': reportType,
        'description': description,
        'logId': logId,
        'evidenceUrls': evidenceUrls,
        'status': 'pending',
        'timestamp': FieldValue.serverTimestamp(),
        'priority': _getReportPriority(reportType),
      };

      await _firestore.collection('reports').doc(reportId).set(reportData);

      // ✅ NOTIFY ADMIN (you can add push notifications here)
      await _notifyAdmins(reportId, reportType);

      return {
        'success': true,
        'message': '✅ Report submitted successfully',
        'reportId': reportId,
      };
    } catch (e) {
      return {'success': false, 'message': 'Error submitting report: $e'};
    }
  }

  // ✅ GET USER'S REPORT HISTORY
  Stream<QuerySnapshot> getUserReports(String userId) {
    return _firestore
        .collection('reports')
        .where('reporterId', isEqualTo: userId)
        .orderBy('timestamp', descending: true)
        .snapshots();
  }

  // ✅ ADMIN: GET ALL PENDING REPORTS
  Stream<QuerySnapshot> getPendingReports() {
    return _firestore
        .collection('reports')
        .where('status', isEqualTo: 'pending')
        .orderBy('priority', descending: true)
        .orderBy('timestamp', descending: true)
        .snapshots();
  }

  // ✅ HELPER METHODS
  String _getReportPriority(String reportType) {
    switch (reportType) {
      case 'harassment':
      case 'assault':
        return 'critical';
      case 'reckless_driving':
      case 'non_payment':
        return 'high';
      case 'rude_behavior':
      case 'overcharging':
        return 'medium';
      default:
        return 'low';
    }
  }

  Future<void> _notifyAdmins(String reportId, String reportType) async {
    // Implementation for admin notifications
    // This could be Firebase Cloud Messaging, email, etc.
    debugPrint('🔄 Admin notified: $reportType - $reportId');
  }

  // ✅ DISTANCE CALCULATION FOR AUTO-REMOVE
  double _calculateDistance(LatLng a, LatLng b) {
    const R = 6371;
    final dLat = _degToRad(b.latitude - a.latitude);
    final dLon = _degToRad(b.longitude - a.longitude);
    final calc = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degToRad(a.latitude)) *
            math.cos(_degToRad(b.latitude)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return R * 2 * math.atan2(math.sqrt(calc), math.sqrt(1 - calc));
  }

  double _degToRad(double deg) => deg * math.pi / 180;
}