import 'dart:convert';
import 'dart:typed_data' show Uint8List;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart' show TextStyle;
import 'package:image/image.dart' show Image;

import '../utils/text_image_renderer.dart';
import 'barcode.dart';
import 'capability_profile.dart';
import 'enums.dart';
import 'generator.dart';
import 'print_column.dart';
import 'qrcode.dart';
import 'text_styles.dart';

/// High-level ESC/POS ticket builder.
///
/// Wraps [Generator] and accumulates all byte output into a single buffer.
/// Call [bytes] when done to get the complete byte sequence to send to the
/// printer.
///
/// ```dart
/// final profile = await CapabilityProfile.load();
/// final ticket = Ticket(PaperSize.mm80, profile);
/// ticket.text('Hello!', styles: TextStyles(bold: true, align: PrintAlign.center));
/// await ticket.textRaster('欢迎光临！');
/// await ticket.textRaster('مرحبا!', textDirection: ui.TextDirection.rtl);
/// ticket.hr();
/// ticket.cut();
/// await manager.printTicket(ticket);
/// ```
class Ticket {
  Ticket(
    PaperSize paperSize,
    CapabilityProfile profile, {
    Codec codec = latin1,
  }) : _gen = Generator(paperSize, profile, codec: codec);

  /// Create a [Ticket] with the bundled default [CapabilityProfile] loaded
  /// automatically — no need to call [CapabilityProfile.load] yourself.
  ///
  /// Optionally pass [additionalProfile] to augment the internal default with
  /// extra code pages. The additional profile's entries are **merged on top**
  /// of the default — they extend it rather than replace it. Entries from
  /// [additionalProfile] take precedence when both define the same code page ID.
  ///
  /// ```dart
  /// // Simplest usage — default profile loaded internally:
  /// final ticket = await Ticket.create(PaperSize.mm80);
  ///
  /// // With an extra profile that adds vendor-specific code pages:
  /// final extra = await CapabilityProfile.load(name: 'myPrinter');
  /// final ticket = await Ticket.create(PaperSize.mm80, additionalProfile: extra);
  /// ```
  static Future<Ticket> create(
    PaperSize paperSize, {
    CapabilityProfile? additionalProfile,
    Codec codec = latin1,
  }) async {
    final defaultProfile = await CapabilityProfile.load();
    final profile = additionalProfile != null
        ? defaultProfile.merge(additionalProfile)
        : defaultProfile;

    return Ticket(paperSize, profile, codec: codec);
  }

  final Generator _gen;
  final List<int> _bytes = [];

  /// All accumulated bytes. The returned list is unmodifiable.
  List<int> get bytes => List.unmodifiable(_bytes);

  /// Clear the accumulated bytes (start a fresh ticket).
  void clear() => _bytes.clear();

  /// Reset printer and clear style state.
  void reset() => _bytes.addAll(_gen.reset());

  /// Set a global code table that persists even after [reset].
  void setGlobalCodeTable(String? codeTable) {
    return _bytes.addAll(_gen.setGlobalCodeTable(codeTable));
  }

  /// Set a global font.
  void setGlobalFont(FontType? font) => _bytes.addAll(_gen.setGlobalFont(font));

  /// Print [text] using the printer's native codec (Latin-1 by default).
  ///
  /// Use this for scripts the printer can encode natively (ASCII, Latin, etc.).
  /// For multi-script text — Chinese, Japanese, Korean, Arabic, Devanagari,
  /// Thai, Cyrillic, etc. — use [textRaster] instead.
  ///
  /// - [styles] — bold, underline, font, alignment, and other ESC/POS styles.
  /// - [linesAfter] — blank lines emitted after the text.
  /// - [maxCharsPerLine] — wraps text at this column count.
  ///
  /// Example:
  /// ```dart
  /// ticket.text('Hello!', styles: TextStyles(bold: true));
  /// ticket.text('Total: \$9.99', styles: TextStyles(align: PrintAlign.right));
  /// ```
  void text(
    String text, {
    TextStyles styles = const TextStyles(),
    int linesAfter = 0,
    int? maxCharsPerLine,
  }) {
    _bytes.addAll(
      _gen.text(
        text,
        styles: styles,
        linesAfter: linesAfter,
        maxCharsPerLine: maxCharsPerLine,
      ),
    );
  }

  /// Print [text] as a raster bitmap rendered by Flutter's text engine.
  ///
  /// Use this for scripts that thermal printers cannot encode natively —
  /// Chinese, Japanese, Korean, Arabic, Devanagari, Thai, Cyrillic, etc.
  /// The text is rendered line-by-line, keeping each `GS v 0` block small
  /// enough for the printer's receive buffer.
  ///
  /// - [textStyle] — [TextStyle] controlling font size, weight, decoration,
  ///   etc. When omitted or when [TextStyle.fontSize] is `null`, the font
  ///   size defaults to **24 pt**.
  /// - [textDirection] — pass [ui.TextDirection.rtl] for Arabic, Hebrew, etc.
  /// - [align] — horizontal alignment of the bitmap image on the receipt.
  /// - [linesAfter] — blank lines fed after the rendered text.
  ///
  /// Example:
  /// ```dart
  /// await ticket.textRaster('欢迎光临！');
  /// await ticket.textRaster(
  ///   'مرحبا بكم!',
  ///   textStyle: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
  ///   textDirection: ui.TextDirection.rtl,
  ///   align: PrintAlign.right,
  /// );
  /// ```
  Future<void> textRaster(
    String text, {
    TextStyle? textStyle,
    ui.TextDirection textDirection = ui.TextDirection.ltr,
    PrintAlign align = PrintAlign.left,
    int linesAfter = 0,
  }) async {
    final lines = await renderTextLinesAsImages(
      text,
      textStyle: textStyle,
      maxWidth: _gen.paperSize.widthPixels.toDouble(),
      textDirection: textDirection,
    );

    for (final line in lines) {
      imageRaster(line, align: align);
    }

    if (linesAfter > 0) _bytes.addAll(_gen.feed(linesAfter));
  }

  /// Print pre-encoded bytes as text.
  void textEncoded(
    Uint8List textBytes, {
    TextStyles styles = const TextStyles(),
    int linesAfter = 0,
    int? maxCharsPerLine,
  }) {
    return _bytes.addAll(
      _gen.textEncoded(
        textBytes,
        styles: styles,
        linesAfter: linesAfter,
        maxCharsPerLine: maxCharsPerLine,
      ),
    );
  }

  /// Send arbitrary raw ESC/POS bytes.
  void rawBytes(List<int> cmd) => _bytes.addAll(_gen.rawBytes(cmd));

  /// Print a horizontal separator line.
  void separator({String char = '-', int? length, int linesAfter = 0}) {
    return _bytes.addAll(
      _gen.separator(
        char: char,
        length: length,
        linesAfter: linesAfter,
      ),
    );
  }

  /// Print a table row.
  void row(
    List<PrintColumn> cols, {
    bool multiLine = true,
    int columnGap = 1,
  }) {
    return _bytes.addAll(
      _gen.row(
        cols,
        multiLine: multiLine,
        columnGap: columnGap,
      ),
    );
  }

  /// Emit empty newline using ESC d [n] lines (0–255).
  void feed([int n = 1]) => _bytes.addAll(_gen.feed(n));

  /// Emit [n] empty newlines.
  void emptyLines([int n = 1]) => _bytes.addAll(_gen.emptyLines(n));

  /// Reverse feed [n] lines (if supported by the printer).
  void reverseFeed([int n = 1]) => _bytes.addAll(_gen.reverseFeed(n));

  /// Print a barcode.
  void barcode(
    String data, {
    BarcodeType type = BarcodeType.code128,
    int? width,
    int? height,
    BarcodeTextFont? textFont,
    BarcodeTextPosition textPosition = BarcodeTextPosition.below,
    PrintAlign align = PrintAlign.center,
  }) {
    return _bytes.addAll(
      _gen.barcode(
        data,
        type: type,
        width: width,
        height: height,
        textFont: textFont,
        textPosition: textPosition,
        align: align,
      ),
    );
  }

  /// Print a QR code using native printer encoding.
  void qrcode(
    String text, {
    PrintAlign align = PrintAlign.center,
    QRSize size = QRSize.size4,
    QRCorrection cor = QRCorrection.L,
  }) {
    return _bytes.addAll(
      _gen.qrcode(
        text,
        align: align,
        size: size,
        cor: cor,
      ),
    );
  }

  /// Print image using ESC * (column format).
  void image(
    Image img, {
    PrintAlign align = PrintAlign.center,
    bool isDoubleDensity = true,
    int? maxWidth,
    int? maxHeight,
  }) {
    return _bytes.addAll(
      _gen.printImage(
        img,
        align: align,
        isDoubleDensity: isDoubleDensity,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
      ),
    );
  }

  /// Print image using GS v 0 or GS ( L (raster format).
  void imageRaster(
    Image img, {
    PrintAlign align = PrintAlign.center,
    bool highDensityHorizontal = true,
    bool highDensityVertical = true,
    PrintImageMode imageFn = PrintImageMode.bitImageRaster,
    int? maxWidth,
    int? maxHeight,
  }) {
    return _bytes.addAll(
      _gen.imageRaster(
        img,
        align: align,
        highDensityHorizontal: highDensityHorizontal,
        highDensityVertical: highDensityVertical,
        imageMode: imageFn,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
      ),
    );
  }

  /// Cut the paper (full or partial).
  void cut({PrintCutMode mode = PrintCutMode.full, int linesBefore = 0}) {
    return _bytes.addAll(_gen.cut(mode: mode, linesBefore: linesBefore));
  }

  /// Beep the printer speaker [n] times.
  void beep({
    int n = 3,
    BeepDuration duration = BeepDuration.beep450ms,
  }) {
    return _bytes.addAll(
      _gen.beep(
        n: n,
        duration: duration,
      ),
    );
  }

  /// Open cash drawer on [pin] (default: pin 2).
  void openCashDrawer({CashDrawer pin = CashDrawer.pin2}) {
    return _bytes.addAll(_gen.drawer(pin: pin));
  }

  /// Print the full character code table (for debugging).
  void printCodeTable({String? codeTable}) {
    return _bytes.addAll(_gen.printCodeTable(codeTable: codeTable));
  }

  /// Set print density / speech level (printer-model specific).
  void printSpeech(int level) => _bytes.addAll(_gen.printSpeech(level));
}
