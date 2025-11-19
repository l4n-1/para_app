// lib/widgets/compact_ads_button.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:para2/services/auth_service.dart';

class CompactAdsButton extends StatefulWidget {
  final VoidCallback? onPointsUpdate;

  const CompactAdsButton({super.key, this.onPointsUpdate});

  @override
  State<CompactAdsButton> createState() => _CompactAdsButtonState();
}

class _CompactAdsButtonState extends State<CompactAdsButton> {
  final AuthService _authService = AuthService();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  int _currentPoints = 0;
  bool _isWatchingAd = false;
  bool _showPointsPopup = false;

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
      // Simulate ad watching
      await Future.delayed(const Duration(seconds: 3));

      // Add points
      await _authService.addUserPoints(user.uid, 10);
      await _loadUserPoints();

      widget.onPointsUpdate?.call();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🎉 +10 Para! Coins earned!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Failed to earn coins: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isWatchingAd = false;
          _showPointsPopup = false;
        });
      }
    }
  }

  void _showPointsInfo() {
    setState(() {
      _showPointsPopup = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Compact Ads Button
        Container(
          decoration: BoxDecoration(
            color: Colors.blueAccent,
            borderRadius: BorderRadius.circular(25),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(25),
              onTap: _showPointsInfo,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _isWatchingAd
                        ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(Colors.white),
                      ),
                    )
                        : const Icon(Icons.emoji_events, color: Colors.white, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      _currentPoints.toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        // Points Popup
        if (_showPointsPopup)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Para! Coins',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Balance: $_currentPoints coins',
                  style: const TextStyle(
                    color: Colors.green,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Watch ads to earn coins for ride discounts!',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isWatchingAd ? null : _watchAdForPoints,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      foregroundColor: Colors.white,
                    ),
                    child: _isWatchingAd
                        ? const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation(Colors.white),
                          ),
                        ),
                        SizedBox(width: 8),
                        Text('Watching Ad...'),
                      ],
                    )
                        : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.play_arrow, size: 16),
                        SizedBox(width: 4),
                        Text('Watch Ad (+10 coins)'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () {
                      setState(() {
                        _showPointsPopup = false;
                      });
                    },
                    child: const Text(
                      'Close',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}