import 'dart:ui' as ui;

import 'package:flutter/painting.dart' show TextStyle;

import 'enums.dart';

/// A single column in a [rowRaster] print call.
///
/// Unlike [PrintColumn] which uses printer-native ESC/POS text styles,
/// this class uses Flutter's [TextStyle] so you can render any font, script,
/// or style that Flutter supports — the text is rasterised into an image
/// before being sent to the printer.
///
/// Columns are sized proportionally using [flex].
///
/// ```dart
/// await ticket.rowRaster([
///   PrintRasterColumn(text: '商品', flex: 2),
///   PrintRasterColumn(
///     text: 'السعر',
///     flex: 1,
///     textDirection: ui.TextDirection.rtl,
///     align: PrintAlign.right,
///   ),
/// ]);
/// ```
class PrintRasterColumn {
  PrintRasterColumn({
    required this.text,
    this.flex = 1,
    this.align = PrintAlign.left,
    this.style,
    this.textDirection = ui.TextDirection.ltr,
  }) {
    if (flex < 1) {
      throw ArgumentError.value(flex, 'flex', 'Column flex must be ≥ 1');
    }
  }

  final String text;
  final int flex;
  final PrintAlign align;
  final TextStyle? style;
  final ui.TextDirection textDirection;
}
