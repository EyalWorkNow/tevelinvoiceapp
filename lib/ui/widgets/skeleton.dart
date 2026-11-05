import 'package:flutter/material.dart';

import '../strings_he.dart';
import '../theme.dart';

/// Loading placeholder rows (spec V2 §15.4: skeleton instead of spinner).
/// Static blocks, no shimmer, so it costs nothing and respects Reduce Motion.
class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.rows = 5});

  final int rows;

  @override
  Widget build(BuildContext context) {
    final c = context.palette.line;
    Widget bar(double widthFactor, double height) => FractionallySizedBox(
      alignment: AlignmentDirectional.centerStart,
      widthFactor: widthFactor,
      child: Container(
        height: height,
        decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(6)),
      ),
    );
    return Semantics(
      label: DsStrings.loading,
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < rows; i++)
            SizedBox(
              height: Hit.row,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.page, vertical: Space.m),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [bar(i.isEven ? 0.6 : 0.45, 14), bar(0.3, 10)],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
