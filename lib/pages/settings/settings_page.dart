//holder, calls role-specific settings layouts
import 'package:flutter/material.dart';
import 'package:para2/pages/settings/PHsettings.dart';
import 'package:para2/pages/settings/THsettings.dart';

class SettingsPage extends StatelessWidget {
  final String role;
  const SettingsPage({super.key, required this.role});

  @override
  Widget build(BuildContext context) {
    Widget content;

    if (role == 'tsuperhero') {
      content = const THsettings();
    } else {
      content = const PHsettings();
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      backgroundColor: Colors.grey[100],
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: content, // role-specific layout goes here
        ),
      ),
    );
  }
}
