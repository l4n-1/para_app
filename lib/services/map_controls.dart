import 'package:flutter/material.dart';

/// Small reusable floating action button used in map UI.
class SmallActionButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final Color iconColor;

  const SmallActionButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.iconColor = Colors.blue,
  });

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      mini: true,
      backgroundColor: Colors.white,
      onPressed: onPressed,
      child: Icon(icon, color: iconColor, size: 20),
    );
  }
}