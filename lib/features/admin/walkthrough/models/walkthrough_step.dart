import 'package:flutter/material.dart';

class WalkthroughStep {
  final GlobalKey key;
  final String title;
  final String description;

  const WalkthroughStep({
    required this.key,
    required this.title,
    required this.description,
  });
}