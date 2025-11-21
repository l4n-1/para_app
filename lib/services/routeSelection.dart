import 'package:flutter/material.dart';
import 'package:para2/services/routeSelection.dart';

class Routeselection extends StatelessWidget {
  const Routeselection({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () {
            RouteSelectionService.selectRoute(context);
          },
          child: const Text('Select Route'),
        ),
      ),
    );
  }
}