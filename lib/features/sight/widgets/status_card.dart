import 'package:flutter/material.dart';

class StatusCard extends StatelessWidget {
  final String statusText;
  final Color activeColor;

  const StatusCard({
    super.key,
    required this.statusText,
    required this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(
        minHeight: 60,
      ),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: activeColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: activeColor,
          width: 1.5,
        ),
      ),
      child: Center(
        child: Text(
          statusText,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
