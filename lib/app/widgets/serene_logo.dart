import 'package:flutter/material.dart';

/// Chooses the original brand artwork for the current surface theme.
class SereneLogo extends StatelessWidget {
  const SereneLogo({super.key, this.width = 180}) : isHorizontal = false;

  const SereneLogo.horizontal({super.key, this.width = 112})
    : isHorizontal = true;

  final double width;
  final bool isHorizontal;

  @override
  Widget build(BuildContext context) {
    final variant = Theme.of(context).brightness == Brightness.dark
        ? 'dark'
        : 'light';
    final prefix = isHorizontal ? 'logo_h' : 'logo';
    final asset = 'assets/icons/${prefix}_$variant.png';
    if (isHorizontal) {
      final height = width / 3;
      // Keep the supplied artwork intact and insert spacing at the transparent
      // boundary between the symbol (left 30%) and wordmark (right 70%).
      Widget piece(double fraction, Alignment alignment) => ClipRect(
        child: SizedBox(
          width: width * fraction,
          height: height,
          child: OverflowBox(
            alignment: alignment,
            minWidth: width,
            maxWidth: width,
            minHeight: height,
            maxHeight: height,
            child: Image.asset(
              asset,
              width: width,
              height: height,
              fit: BoxFit.contain,
              excludeFromSemantics: true,
              filterQuality: FilterQuality.high,
              cacheWidth: (width * MediaQuery.devicePixelRatioOf(context))
                  .ceil(),
              gaplessPlayback: true,
            ),
          ),
        ),
      );
      return Semantics(
        label: 'serene',
        image: true,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          textDirection: TextDirection.ltr,
          children: [
            piece(0.30, Alignment.centerLeft),
            const SizedBox(width: 6),
            piece(0.70, Alignment.centerRight),
          ],
        ),
      );
    }
    return Image.asset(
      asset,
      width: width,
      height: width / (isHorizontal ? 3 : 1.5),
      fit: BoxFit.contain,
      semanticLabel: 'serene',
      filterQuality: FilterQuality.high,
      cacheWidth: (width * MediaQuery.devicePixelRatioOf(context)).ceil(),
      gaplessPlayback: true,
    );
  }
}
