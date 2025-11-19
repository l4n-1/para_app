// lib/widgets/enhanced_para_button.dart
import 'package:flutter/material.dart';
import 'dart:async';

class EnhancedParaButton extends StatefulWidget {
  final VoidCallback onParaPressed;
  final bool isEnabled;

  const EnhancedParaButton({
    super.key,
    required this.onParaPressed,
    required this.isEnabled,
  });

  @override
  State<EnhancedParaButton> createState() => _EnhancedParaButtonState();
}

class _EnhancedParaButtonState extends State<EnhancedParaButton> {
  bool _isHolding = false;
  int _holdProgress = 0;
  Timer? _holdTimer;
  int _pressCount = 0;
  DateTime? _lastPressTime;

  static const int holdDuration = 3; // seconds
  static const int cooldownDuration = 15; // seconds
  static const int maxPresses = 2;

  @override
  void dispose() {
    _holdTimer?.cancel();
    super.dispose();
  }

  void _startHold() {
    if (!widget.isEnabled) return;
    if (_pressCount >= maxPresses) {
      _showMaxPressesWarning();
      return;
    }

    if (_lastPressTime != null) {
      final cooldownEnd = _lastPressTime!.add(const Duration(seconds: cooldownDuration));
      if (DateTime.now().isBefore(cooldownEnd)) {
        _showCooldownWarning(cooldownEnd);
        return;
      }
    }

    setState(() {
      _isHolding = true;
      _holdProgress = 0;
    });

    _holdTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      setState(() {
        _holdProgress += 10; // 100ms increments for 3 seconds total
      });

      if (_holdProgress >= 100) {
        timer.cancel();
        _executePara();
      }
    });
  }

  void _cancelHold() {
    _holdTimer?.cancel();
    setState(() {
      _isHolding = false;
      _holdProgress = 0;
    });
  }

  void _executePara() {
    setState(() {
      _isHolding = false;
      _holdProgress = 0;
      _pressCount++;
      _lastPressTime = DateTime.now();
    });

    widget.onParaPressed();

    // Show success message
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('🚍 PARA! signal sent! (${_pressCount}/$maxPresses used)'),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );

    // Reset press count after cooldown
    Future.delayed(const Duration(seconds: cooldownDuration), () {
      if (mounted) {
        setState(() {
          _pressCount = 0;
        });
      }
    });
  }

  void _showMaxPressesWarning() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('❌ Maximum PARA! presses reached. Wait for cooldown.'),
        backgroundColor: Colors.orange,
      ),
    );
  }

  void _showCooldownWarning(DateTime cooldownEnd) {
    final remaining = cooldownEnd.difference(DateTime.now()).inSeconds;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('⏳ Cooldown: ${remaining}s remaining'),
        backgroundColor: Colors.blue,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _startHold(),
      onTapUp: (_) => _cancelHold(),
      onTapCancel: _cancelHold,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
        decoration: BoxDecoration(
          color: widget.isEnabled
              ? (_isHolding ? Colors.orange : Colors.greenAccent.shade700)
              : Colors.grey,
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _isHolding ? 'HOLDING... $_holdProgress%' : 'PARA!',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: _isHolding ? 14 : 18,
                color: Colors.white,
              ),
            ),
            if (_isHolding) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: _holdProgress / 100,
                backgroundColor: Colors.white.withOpacity(0.3),
                color: Colors.white,
              ),
            ],
            if (_pressCount > 0) ...[
              const SizedBox(height: 4),
              Text(
                '${_pressCount}/$maxPresses presses',
                style: const TextStyle(
                  fontSize: 10,
                  color: Colors.white,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}