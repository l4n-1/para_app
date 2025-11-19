// lib/pages/biyahe/report_dialog.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:para2/services/qr_boarding_service.dart';

class ReportDialog extends StatefulWidget {
  final Map<String, dynamic> logData;
  final String userType;

  const ReportDialog({
    super.key,
    required this.logData,
    required this.userType,
  });

  @override
  State<ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<ReportDialog> {
  final QRBoardingService _qrService = QRBoardingService();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String _selectedReportType = 'non_payment';
  final TextEditingController _descriptionController = TextEditingController();
  final List<String> _evidenceUrls = [];
  bool _isSubmitting = false;

  final List<Map<String, String>> _reportTypes = [
    {'value': 'non_payment', 'label': 'Non-Payment'},
    {'value': 'harassment', 'label': 'Harassment'},
    {'value': 'reckless_driving', 'label': 'Reckless Driving'},
    {'value': 'rude_behavior', 'label': 'Rude Behavior'},
    {'value': 'overcharging', 'label': 'Overcharging'},
    {'value': 'smoking', 'label': 'Smoking in Vehicle'},
    {'value': 'other', 'label': 'Other Issue'},
  ];

  @override
  Widget build(BuildContext context) {
    final reportedUser = widget.userType == 'pasahero'
        ? 'Driver (${widget.logData['driverId']?.toString().substring(0, 8)})'
        : 'Passenger (${widget.logData['passengerName']})';

    return AlertDialog(
      title: const Text('Report User'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Reporting: $reportedUser'),
            const SizedBox(height: 16),

            // Report Type
            const Text('Issue Type:', style: TextStyle(fontWeight: FontWeight.bold)),
            DropdownButton<String>(
              value: _selectedReportType,
              isExpanded: true,
              onChanged: (String? newValue) {
                setState(() {
                  _selectedReportType = newValue!;
                });
              },
              items: _reportTypes.map((type) {
                return DropdownMenuItem<String>(
                  value: type['value'],
                  child: Text(type['label']!),
                );
              }).toList(),
            ),

            const SizedBox(height: 16),

            // Description
            const Text('Description:', style: TextStyle(fontWeight: FontWeight.bold)),
            TextField(
              controller: _descriptionController,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'Please describe what happened...',
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 16),

            // Evidence Upload
            const Text('Evidence (Photos):', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _buildEvidenceSection(),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isSubmitting ? null : _submitReport,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
          ),
          child: _isSubmitting
              ? const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
            ),
          )
              : const Text('Submit Report'),
        ),
      ],
    );
  }

  Widget _buildEvidenceSection() {
    return Column(
      children: [
        // Current evidence
        if (_evidenceUrls.isNotEmpty) ...[
          Wrap(
            spacing: 8,
            children: _evidenceUrls.map((url) {
              return Chip(
                label: Text('Evidence ${_evidenceUrls.indexOf(url) + 1}'),
                onDeleted: () {
                  setState(() {
                    _evidenceUrls.remove(url);
                  });
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
        ],

        // Add evidence button
        ElevatedButton.icon(
          onPressed: _addEvidence,
          icon: const Icon(Icons.camera_alt),
          label: const Text('Add Photo Evidence'),
        ),
      ],
    );
  }

  Future<void> _addEvidence() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.camera);

    if (pickedFile != null) {
      // In production, you would upload to Firebase Storage
      // For now, we'll use the file path as a placeholder
      setState(() {
        _evidenceUrls.add(pickedFile.path);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Photo added as evidence')),
      );
    }
  }

  Future<void> _submitReport() async {
    final user = _auth.currentUser;
    if (user == null || _descriptionController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please provide a description')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final reportedUserId = widget.userType == 'pasahero'
          ? widget.logData['driverId']
          : widget.logData['passengerId'];

      final result = await _qrService.submitReport(
        reporterId: user.uid,
        reportedUserId: reportedUserId,
        reportType: _selectedReportType,
        description: _descriptionController.text.trim(),
        logId: widget.logData['logId'],
        evidenceUrls: _evidenceUrls,
      );

      if (result['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message']),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message']),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error submitting report: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isSubmitting = false);
    }
  }
}