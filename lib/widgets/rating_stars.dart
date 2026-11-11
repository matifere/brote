import 'package:flutter/material.dart';

/// Read-only row of 5 stars for a rating.
class RatingStars extends StatelessWidget {
  final int stars;
  final double size;

  const RatingStars({super.key, required this.stars, this.size = 14});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.tertiary;
    return Semantics(
      label: '$stars de 5 estrellas',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(
          5,
          (i) => Icon(
            i < stars ? Icons.star_rounded : Icons.star_outline_rounded,
            size: size,
            color: i < stars ? color : color.withValues(alpha: 0.45),
          ),
        ),
      ),
    );
  }
}
