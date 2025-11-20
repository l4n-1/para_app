import 'package:flutter/material.dart';

class SnackbarService {
  /// Show a floating snackbar styled as a black rounded container positioned
  /// near the top with dynamic width based on text length.
  static void show(BuildContext context, String message, {Duration? duration}) {
    final snack = SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Colors.transparent,
      elevation: 0,
      duration: duration ?? const Duration(seconds: 2),
      margin: const EdgeInsets.only(top: 30, bottom: 730), // left/right will be handled inside
      content: Row(
        mainAxisSize: MainAxisSize.min, // <-- shrink to fit content
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible( // optional, prevents overflow for very long text
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 12),
              decoration: BoxDecoration(
                color: const Color.fromARGB(179, 21, 5, 43),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(snack);
  }
}
