// lib/widgets/points_rewards_widget.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:para2/services/ad_service.dart';
import 'package:para2/services/auth_service.dart';

class PointsRewardsWidget extends StatefulWidget {
  final VoidCallback? onPointsUpdate;

  const PointsRewardsWidget({super.key, this.onPointsUpdate});

  @override
  State<PointsRewardsWidget> createState() => _PointsRewardsWidgetState();
}

class _PointsRewardsWidgetState extends State<PointsRewardsWidget> {
  final AuthService _authService = AuthService();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  int _currentPoints = 0;
  bool _isWatchingAd = false;
  bool _showPointsInfo = false;

  @override
  void initState() {
    super.initState();
    _loadUserPoints();
  }

  Future<void> _loadUserPoints() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final points = await _authService.getUserPoints(user.uid);
      setState(() {
        _currentPoints = points;
      });
    } catch (e) {
      debugPrint('Error loading points: $e');
    }
  }

  Future<void> _watchAdForPoints() async {
    final user = _auth.currentUser;
    if (user == null || _isWatchingAd) return;

    setState(() {
      _isWatchingAd = true;
    });

    try {
      // Show demo rewarded ad
      final adCompleted = await AdService.showDemoRewardedAd();

      if (adCompleted) {
        // Add points to user account
        await _authService.addUserPoints(user.uid, AdService.pointsPerAd);

        // Reload points
        await _loadUserPoints();

        // Notify parent widget
        widget.onPointsUpdate?.call();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('🎉 You earned ${AdService.pointsPerAd} points!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Failed to earn points: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isWatchingAd = false;
        });
      }
    }
  }

  void _showPointsInfoDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.emoji_events, color: Colors.amber),
            SizedBox(width: 8),
            Text('Points & Rewards'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Earn points and get ride discounts!',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _buildInfoRow('👀 Watch an ad', '${AdService.pointsPerAd} points'),
            _buildInfoRow('🎁 Redeem ${AdService.pointsForDiscount} points', '₱${AdService.discountAmount} discount'),
            _buildInfoRow('💰 Digital payments', 'Earn points faster'),
            const SizedBox(height: 8),
            Text(
              'Current balance: $_currentPoints points',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.green,
              ),
            ),
            if (AdService.canRedeemDiscount(_currentPoints))
              Text(
                '🎉 You can get a ₱${AdService.discountAmount} discount!',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          if (AdService.canRedeemDiscount(_currentPoints))
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _showRedeemDialog();
              },
              child: const Text('Redeem Discount'),
            ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(title)),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  void _showRedeemDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Redeem Points'),
        content: Text(
          'Redeem ${AdService.pointsForDiscount} points for a ₱${AdService.discountAmount} discount on your next ride?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Discount will be applied to your next ride!'),
                  backgroundColor: Colors.green,
                ),
              );
            },
            child: const Text('Redeem'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue[100]!),
      ),
      child: Column(
        children: [
          // Points Display
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.emoji_events, color: Colors.amber, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Points: $_currentPoints',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  IconButton(
                    onPressed: _showPointsInfoDialog,
                    icon: const Icon(Icons.info_outline, size: 20),
                    tooltip: 'Points Info',
                  ),
                  const SizedBox(width: 8),
                  _buildProgressIndicator(),
                ],
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Watch Ad Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isWatchingAd ? null : _watchAdForPoints,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              icon: _isWatchingAd
                  ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(Colors.white),
                ),
              )
                  : const Icon(Icons.play_arrow),
              label: _isWatchingAd
                  ? const Text('Watching Ad...')
                  : const Text('Watch Ad to Earn Points'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressIndicator() {
    final pointsNeeded = AdService.pointsNeededForNextDiscount(_currentPoints);
    final progress = _currentPoints % AdService.pointsForDiscount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          '$pointsNeeded to next discount',
          style: const TextStyle(fontSize: 10, color: Colors.grey),
        ),
        const SizedBox(height: 4),
        Container(
          width: 60,
          height: 6,
          decoration: BoxDecoration(
            color: Colors.grey[300],
            borderRadius: BorderRadius.circular(3),
          ),
          child: Stack(
            children: [
              Container(
                width: (progress / AdService.pointsForDiscount) * 60,
                decoration: BoxDecoration(
                  color: Colors.green,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}