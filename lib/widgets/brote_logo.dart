import 'package:flutter/material.dart';

/// Official Brote Logo generated with Stitch
class BroteLogo extends StatelessWidget {
  final double size;
  final bool useDarkSquircle;
  final double? borderRadius;

  const BroteLogo({
    super.key,
    this.size = 40,
    this.useDarkSquircle = true,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final assetPath = useDarkSquircle
        ? 'assets/images/logo.png'
        : 'assets/images/logo_mark.png';

    final effectiveRadius = borderRadius ?? (size * 0.25);

    return ClipRRect(
      borderRadius: BorderRadius.circular(effectiveRadius),
      child: Image.asset(
        assetPath,
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          // Fallback in case assets are initializing
          return Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: useDarkSquircle ? const Color(0xFF161820) : Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(effectiveRadius),
            ),
            child: Icon(
              Icons.eco_rounded,
              size: size * 0.6,
              color: useDarkSquircle ? const Color(0xFF10B981) : Theme.of(context).colorScheme.onPrimaryContainer,
            ),
          );
        },
      ),
    );
  }
}
