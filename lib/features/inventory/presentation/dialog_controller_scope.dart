import 'package:flutter/material.dart';

/// Keeps form controllers alive until the dialog route has fully unmounted.
class DialogControllerScope extends StatefulWidget {
  const DialogControllerScope({
    required this.controllers,
    required this.child,
    super.key,
  });

  final List<TextEditingController> controllers;
  final Widget child;

  @override
  State<DialogControllerScope> createState() => _DialogControllerScopeState();
}

class _DialogControllerScopeState extends State<DialogControllerScope> {
  @override
  void dispose() {
    for (final controller in widget.controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
