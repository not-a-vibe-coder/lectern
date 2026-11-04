import 'package:flutter/material.dart';

import '../theme/theme.dart';
import '../theme/tokens.dart';

/// The Lectern mark: a sheet of notes on a reading stand with one line
/// highlighted. Below 40 px the simplified small version is used.
class LecternMark extends StatelessWidget {
  const LecternMark({super.key, this.size = 32});
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Image.asset(
      size < 40 ? 'assets/brand/mark-small.png' : 'assets/brand/mark.png',
      width: size,
      height: size,
      filterQuality: FilterQuality.medium,
      gaplessPlayback: true,
    ),
  );
}

/// Mark plus the word "Lectern".
class Wordmark extends StatelessWidget {
  const Wordmark({super.key, this.size = 28, this.color = LecternColors.ink});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Lectern',
    excludeSemantics: true,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        LecternMark(size: size),
        SizedBox(width: size * 0.3),
        Text(
          'Lectern',
          style: TextStyle(
            fontFamily: Fonts.display,
            fontWeight: FontWeight.w600,
            fontSize: size * 0.82,
            height: 1,
            color: color,
            letterSpacing: -0.2,
          ),
        ),
      ],
    ),
  );
}
