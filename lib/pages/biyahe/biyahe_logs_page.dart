// lib/pages/biyahe/biyahe_logs_page.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:para2/services/qr_boarding_service.dart';
import 'package:para2/pages/biyahe/report_dialog.dart';

class BiyaheLogsPage extends StatefulWidget {
  final String userType; // 'pasahero' or 'tsuperhero'

  const BiyaheLogsPage({super.key, required this.userType});

  @override
  State<BiyaheLogsPage> createState() => _BiyaheLogsPageState();
}

class _BiyaheLogsPageState extends State<BiyaheLogsPage> {
  final QRBoardingService _qrService = QRBoardingService();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String _selectedFilter = 'all'; // 'all', 'completed', 'pending'

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('Please log in to view logs')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Biyahe Logs'),
        backgroundColor: const Color.fromARGB(255, 73, 172, 123),
        actions: [
          // Filter Dropdown
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: DropdownButton<String>(
              value: _selectedFilter,
              onChanged: (String? newValue) {
                setState(() {
                  _selectedFilter = newValue!;
                });
              },
              items: const [
                DropdownMenuItem(value: 'all', child: Text('All Rides')),
                DropdownMenuItem(value: 'completed', child: Text('Completed')),
                DropdownMenuItem(value: 'pending', child: Text('Pending Payment')),
              ],
            ),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _qrService.getUserBiyaheLogs(user.uid, userType: widget.userType),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final logs = snapshot.data!.docs;

          // Filter logs based on selection
          final filteredLogs = _selectedFilter == 'all'
              ? logs
              : logs.where((log) {
            final data = log.data() as Map<String, dynamic>;
            if (_selectedFilter == 'completed') {
              return data['rideStatus'] == 'completed';
            } else if (_selectedFilter == 'pending') {
              return data['paymentStatus'] == 'pending';
            }
            return true;
          }).toList();

          if (filteredLogs.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'No ride history yet',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            itemCount: filteredLogs.length,
            itemBuilder: (context, index) {
              final log = filteredLogs[index];
              final data = log.data() as Map<String, dynamic>;

              return _buildLogCard(data);
            },
          );
        },
      ),
    );
  }

  Widget _buildLogCard(Map<String, dynamic> data) {
    final timestamp = (data['timestamp'] as Timestamp).toDate();
    final isCompleted = data['rideStatus'] == 'completed';
    final paymentStatus = data['paymentStatus'] ?? 'pending';
    final fareAmount = data['fareAmount'] ?? 0.0;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ListTile(
        leading: Icon(
          data['type'] == 'boarding' ? Icons.directions_bus : Icons.person,
          color: isCompleted ? Colors.green : Colors.orange,
        ),
        title: Text(
          widget.userType == 'pasahero'
              ? 'Jeepney ${data['jeepneyId']?.toString().substring(0, 8) ?? 'Unknown'}'
              : 'Passenger: ${data['passengerName'] ?? 'Unknown'}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${_formatDate(timestamp)} • ${_formatTime(timestamp)}'),
            Text('Fare: ₱${fareAmount.toStringAsFixed(2)}'),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: _getStatusColor(paymentStatus),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    paymentStatus.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 10,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: _getTypeColor(data['type']),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    data['type']?.toString().toUpperCase() ?? 'UNKNOWN',
                    style: const TextStyle(
                      fontSize: 10,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.report_problem),
          onPressed: () {
            _showReportDialog(data);
          },
          tooltip: 'Report Issue',
        ),
        onTap: () {
          _showLogDetails(data);
        },
      ),
    );
  }

  void _showLogDetails(Map<String, dynamic> data) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ride Details'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDetailRow('Ride ID', data['logId']?.toString() ?? 'N/A'),
              _buildDetailRow('Passenger', data['passengerName']?.toString() ?? 'N/A'),
              _buildDetailRow('Driver', data['driverId']?.toString().substring(0, 8) ?? 'N/A'),
              _buildDetailRow('Jeepney', data['jeepneyId']?.toString() ?? 'N/A'),
              _buildDetailRow('Type', data['type']?.toString() ?? 'N/A'),
              _buildDetailRow('Status', data['rideStatus']?.toString() ?? 'N/A'),
              _buildDetailRow('Payment', data['paymentStatus']?.toString() ?? 'N/A'),
              _buildDetailRow('Fare', '₱${(data['fareAmount'] ?? 0.0).toStringAsFixed(2)}'),
              _buildDetailRow('Date', _formatDate((data['timestamp'] as Timestamp).toDate())),
              _buildDetailRow('Time', _formatTime((data['timestamp'] as Timestamp).toDate())),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          Text(value),
        ],
      ),
    );
  }

  void _showReportDialog(Map<String, dynamic> logData) {
    showDialog(
      context: context,
      builder: (context) => ReportDialog(
        logData: logData,
        userType: widget.userType,
      ),
    );
  }

  // Helper methods
  String _formatDate(DateTime date) {
    return '${date.month}/${date.day}/${date.year}';
  }

  String _formatTime(DateTime date) {
    return '${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'completed':
        return Colors.green;
      case 'pending':
        return Colors.orange;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  Color _getTypeColor(String type) {
    switch (type) {
      case 'boarding':
        return Colors.blue;
      case 'dropoff':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }
}