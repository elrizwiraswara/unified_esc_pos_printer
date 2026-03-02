import 'dart:convert';
import 'dart:typed_data' show Uint8List;

import 'package:image/image.dart';

import '../codec/hex_codec.dart';
import 'barcode.dart';
import 'capability_profile.dart';
import 'commands.dart';
import 'enums.dart';
import 'print_column.dart';
import 'qrcode.dart';
import 'text_styles.dart';

/// Low-level ESC/POS byte-command generator.
///
/// Each method returns a [List<int>] of bytes that can be concatenated and
/// sent directly to a thermal printer.
///
/// Typical usage: build a full ticket via the higher-level [Ticket] class,
/// which wraps this generator and accumulates bytes for you.
class Generator {
  Generator(
    this.paperSize,
    this.profile, {
    this.codec = latin1,
  });

  final PaperSize paperSize;
  final CapabilityProfile profile;
  final Codec codec;

  int _getMaxCharsPerLine(FontType? font) {
    return switch (paperSize) {
      PaperSize.mm58 => PaperSize.mm58.charsPerLine(font),
      PaperSize.mm72 => PaperSize.mm72.charsPerLine(font),
      PaperSize.mm80 => PaperSize.mm80.charsPerLine(font),
    };
  }

  double _getCharWidth(TextStyles styles, {int? maxCharsPerLine}) {
    int charsPerLine = _getCharsPerLine(styles, maxCharsPerLine);
    double charWidth = (paperSize.widthPixels / charsPerLine);
    return charWidth * styles.width.value;
  }

  int _getCharsPerLine(TextStyles styles, int? maxCharsPerLine) {
    if (maxCharsPerLine != null) return maxCharsPerLine;
    if (styles.fontType != null) return _getMaxCharsPerLine(styles.fontType);
    return maxCharsPerLine ?? _getMaxCharsPerLine(styles.fontType);
  }

  Uint8List _encode(String text) {
    // Normalise common look-alike Unicode characters to ASCII equivalents.
    text = text
        .replaceAll('\u2019', "'")
        .replaceAll('\u00B4', "'")
        .replaceAll('\u00BB', '"')
        .replaceAll('\u00A0', ' ')
        .replaceAll('\u2022', '.');

    try {
      return codec.encode(text);
    } catch (_) {
      // Codec (e.g. Latin1) cannot represent some characters – fall back to
      // UTF-8 so the call never crashes.  Most modern thermal printers accept
      // UTF-8; for printers that don't, callers should pre-process the text or
      // use textEncoded() with an appropriate encoding.
      return Uint8List.fromList(utf8.encode(text));
    }
  }

  /// Generate multiple bytes for a number: In lower and higher parts, or more parts as needed.
  ///
  /// [value] Input number
  /// [bytesNb] The number of bytes to output (1 - 4)
  List<int> _intLowHigh(int value, int bytesNb) {
    final dynamic maxInput = 256 << (bytesNb * 8) - 1;

    if (bytesNb < 1 || bytesNb > 4) {
      throw Exception('Can only output 1-4 bytes');
    }

    if (value < 0 || value > maxInput) {
      throw Exception(
        'Number is too large. Can only output up to $maxInput in $bytesNb bytes',
      );
    }

    final List<int> res = <int>[];
    int buf = value;

    for (int i = 0; i < bytesNb; ++i) {
      res.add(buf % 256);
      buf = buf ~/ 256;
    }

    return res;
  }

  /// Extract slices of an image as equal-sized blobs of column-format data.
  ///
  /// [image] Image to extract from
  /// [lineHeight] Printed line height in dots
  List<List<int>> _toColumnFormat(Image imgSrc, int lineHeight) {
    final Image image = Image.from(imgSrc); // make a copy

    // Determine new width: closest integer that is divisible by lineHeight
    final int widthPx = (image.width + lineHeight) - (image.width % lineHeight);
    final int heightPx = image.height;

    // Create a black bottom layer
    final biggerImage = copyResize(
      image,
      width: widthPx,
      height: heightPx,
      interpolation: Interpolation.linear,
    );

    //fill(biggerImage, color: ColorRgb8(0, 0, 0));
    fill(biggerImage, color: ColorRgb8(0, 0, 0));

    // Insert source image into bigger one
    compositeImage(biggerImage, image, dstX: 0, dstY: 0);

    int left = 0;
    final List<List<int>> blobs = [];

    while (left < widthPx) {
      final Image slice = copyCrop(
        biggerImage,
        x: left,
        y: 0,
        width: lineHeight,
        height: heightPx,
      );

      if (slice.numChannels > 2) grayscale(slice);

      final imgBinary =
          (slice.numChannels > 1) ? slice.convert(numChannels: 1) : slice;

      final bytes = imgBinary.getBytes();

      blobs.add(bytes);

      left += lineHeight;
    }

    return blobs;
  }

  /// Scale [image] down (preserving aspect ratio) so it fits within
  /// [maxWidth] x [maxHeight]. Returns the original image if no constraint
  /// is exceeded or both limits are null.
  Image _constrainImage(Image image, int? maxWidth, int? maxHeight) {
    if (maxWidth == null && maxHeight == null) return image;

    double scale = 1.0;

    if (maxWidth != null && image.width > maxWidth) {
      scale = maxWidth / image.width;
    }

    if (maxHeight != null && image.height * scale > maxHeight) {
      scale = maxHeight / image.height;
    }

    if (scale >= 1.0) return image;

    return copyResize(
      image,
      width: (image.width * scale).round(),
      height: (image.height * scale).round(),
    );
  }

  /// Image rasterization
  List<int> _toRasterFormat(Image imgSrc) {
    final Image image = Image.from(imgSrc); // Make a copy
    final int widthPx = image.width;
    final int heightPx = image.height;

    grayscale(image);
    invert(image);

    // R/G/B channels are same -> keep only one channel
    List<int> oneChannelBytes = [];
    final List<int> buffer = image.getBytes(order: ChannelOrder.rgba);

    for (int i = 0; i < buffer.length; i += 4) {
      oneChannelBytes.add(buffer[i]);
    }

    // Add some empty pixels at the end of each line (to make the width divisible by 8)
    if (widthPx % 8 != 0) {
      final targetWidth = (widthPx + 8) - (widthPx % 8);
      final missingPx = targetWidth - widthPx;
      final extra = Uint8List(missingPx);

      oneChannelBytes = List<int>.filled(heightPx * targetWidth, 0);

      for (int i = 0; i < heightPx; i++) {
        // Corrected position calculation
        final pos = (i * widthPx) + i * missingPx;
        oneChannelBytes.insertAll(pos, extra);
      }
    }

    // Pack bits into bytes
    return _packBitsIntoBytes(oneChannelBytes);
  }

  /// Pack 8 greyscale values into a single byte using [kRasterThreshold].
  List<int> _packBitsIntoBytes(List<int> bytes) {
    const int pxPerLine = 8;
    final List<int> res = [];

    for (int i = 0; i < bytes.length; i += pxPerLine) {
      int newVal = 0;

      for (int j = 0; j < pxPerLine; j++) {
        newVal = _transformUint32Bool(
          newVal,
          pxPerLine - j,
          bytes[i + j] > kRasterThreshold,
        );
      }
      // Shift right by 1 bit (the loop processes bits 1–8, not 0–7).
      res.add(newVal ~/ 2);
    }

    return res;
  }

  /// Replaces a single bit in a 32-bit unsigned integer.
  int _transformUint32Bool(int uint32, int shift, bool newValue) {
    return ((0xFFFFFFFF ^ (0x1 << shift)) & uint32) |
        ((newValue ? 1 : 0) << shift);
  }

  /// Reset printer to factory defaults (ESC @).
  List<int> reset() => [...cInit.codeUnits];

  /// Reset only text styles to size-1 defaults.
  List<int> clearStyle() => setStyles(
        const TextStyles(height: TextSize.size1, width: TextSize.size1),
      );

  /// Emit the ESC/POS command to select [codeTable].
  List<int> setGlobalCodeTable(String? codeTable) {
    if (codeTable == null) return [];
    return Uint8List.fromList(
      List<int>.from(cCodeTable.codeUnits)
        ..add(profile.getCodePageId(codeTable)),
    );
  }

  /// Emit the ESC/POS command to select [font].
  List<int> setGlobalFont(FontType? font) {
    if (font == null) return [];
    return font == FontType.fontB ? cFontB.codeUnits : cFontA.codeUnits;
  }

  /// Apply [styles], emitting all relevant ESC/POS style commands.
  List<int> setStyles(TextStyles styles) {
    List<int> bytes = [];

    bytes += codec.encode(styles.align == PrintAlign.left
        ? cAlignLeft
        : (styles.align == PrintAlign.center ? cAlignCenter : cAlignRight));
    bytes += styles.bold ? cBoldOn.codeUnits : cBoldOff.codeUnits;
    bytes += styles.turn90 ? cTurn90On.codeUnits : cTurn90Off.codeUnits;
    bytes += styles.reverse ? cReverseOn.codeUnits : cReverseOff.codeUnits;
    bytes +=
        styles.underline ? cUnderline1dot.codeUnits : cUnderlineOff.codeUnits;

    final FontType font = styles.fontType ?? FontType.fontA;
    bytes += font == FontType.fontB ? cFontB.codeUnits : cFontA.codeUnits;

    bytes += Uint8List.fromList(
      List<int>.from(cSizeGSn.codeUnits)
        ..add(TextSize.decSize(styles.height, styles.width)),
    );

    // Always disable Kanji mode (no hardware multibyte encoding used).
    bytes += cKanjiOff.codeUnits;

    if (styles.codeTable != null) {
      bytes += Uint8List.fromList(
        List<int>.from(cCodeTable.codeUnits)
          ..add(profile.getCodePageId(styles.codeTable)),
      );
    }

    return bytes;
  }

  /// Send arbitrary raw ESC/POS bytes.
  List<int> rawBytes(List<int> cmd) {
    return [...cKanjiOff.codeUnits, ...cmd];
  }

  /// Print [text] with optional [styles].
  List<int> text(
    String text, {
    TextStyles styles = const TextStyles(),
    int linesAfter = 0,
    int? maxCharsPerLine,
  }) {
    return [
      ..._text(
        _encode(text),
        styles: styles,
        maxCharsPerLine: maxCharsPerLine,
      ),
      ...emptyLines(linesAfter + 1),
    ];
  }

  /// Print pre-encoded bytes as text.
  List<int> textEncoded(
    Uint8List textBytes, {
    TextStyles styles = const TextStyles(),
    int linesAfter = 0,
    int? maxCharsPerLine,
  }) {
    return [
      ..._text(textBytes, styles: styles, maxCharsPerLine: maxCharsPerLine),
      ...emptyLines(linesAfter + 1),
    ];
  }

  /// Emit [n] newlines.
  List<int> emptyLines(int n) {
    if (n <= 0) return [];
    return List.filled(n, '\n').join().codeUnits;
  }

  /// Use ESC d command to emit [n] newlines (0–255).
  List<int> feed(int n) {
    if (n <= 0 || n > 255) return [];
    return Uint8List.fromList(List.from(cFeedN.codeUnits)..add(n));
  }

  /// Reverse feed [n] lines (if supported by the printer).
  List<int> reverseFeed(int n) {
    return Uint8List.fromList(List<int>.from(cReverseFeedN.codeUnits)..add(n));
  }

  /// Cut the paper.
  List<int> cut({PrintCutMode mode = PrintCutMode.full, int linesBefore = 0}) {
    return [
      ...emptyLines(linesBefore),
      ...(mode == PrintCutMode.partial
          ? cCutPart.codeUnits
          : cCutFull.codeUnits),
    ];
  }

  /// Beep the printer speaker [n] times.
  ///
  /// Fixes the legacy bug where the method called itself recursively without
  /// actually accumulating the extra bytes (returning early before the
  /// recursive call's return value was used). Replaced with a simple loop.
  List<int> beep({
    int n = 3,
    BeepDuration duration = BeepDuration.beep450ms,
  }) {
    if (n <= 0) return [];

    final List<int> bytes = [];
    int remaining = n;

    while (remaining > 0) {
      final int count = remaining.clamp(1, kMaxBeepCount);

      bytes.addAll(Uint8List.fromList(
        List<int>.from(cBeep.codeUnits)..addAll([count, duration.value]),
      ));

      remaining -= count;
    }

    return bytes;
  }

  /// Open cash drawer connected to [pin] (default: pin 2).
  List<int> drawer({CashDrawer pin = CashDrawer.pin2}) {
    return pin == CashDrawer.pin2
        ? cCashDrawerPin2.codeUnits
        : cCashDrawerPin5.codeUnits;
  }

  /// Print a horizontal separator line.
  ///
  /// [char] is the fill character (single character string).
  /// [length] defaults to the maximum characters per line for the current font.
  List<int> separator({String char = '-', int? length, int linesAfter = 0}) {
    final int n = length ?? _getMaxCharsPerLine(null);
    final String ch1 = char.length == 1 ? char : char[0];
    return text(List.filled(n, ch1).join(), linesAfter: linesAfter);
  }

  /// Print a table row.
  ///
  /// [cols] must sum to exactly 12 in total width.
  /// Set [multiLine] to true (default) to automatically wrap overflowing
  /// column content to a subsequent row.
  List<int> row(
    List<PrintColumn> cols, {
    bool multiLine = true,
    int columnGap = 1,
  }) {
    final int totalFlex = cols.fold(0, (sum, c) => sum + c.flex);
    final int paperPx = paperSize.widthPixels;

    List<int> bytes = [];
    bool isNextRow = false;
    final List<PrintColumn> nextRow = [];

    int runningFlex = 0;
    for (int i = 0; i < cols.length; i++) {
      final int fromPx =
          i == 0 ? 0 : (paperPx * runningFlex / totalFlex).round();

      runningFlex += cols[i].flex;

      final bool isLastCol = i == cols.length - 1;
      final int toPx = (paperPx * runningFlex / totalFlex).round() -
          (isLastCol ? 0 : columnGap);

      final double charWidth = _getCharWidth(cols[i].styles);
      final int maxCharsNb = ((toPx - fromPx) / charWidth).floor();

      Uint8List encoded = cols[i].textEncoded != null
          ? cols[i].textEncoded!
          : _encode(cols[i].text);

      if (multiLine && encoded.length > maxCharsNb) {
        nextRow.add(
          PrintColumn(
            textEncoded: encoded.sublist(maxCharsNb),
            flex: cols[i].flex,
            styles: cols[i].styles,
          ),
        );

        encoded = encoded.sublist(0, maxCharsNb);
        isNextRow = true;
      } else {
        nextRow.add(
          PrintColumn(
            text: '',
            flex: cols[i].flex,
            styles: cols[i].styles,
          ),
        );
      }

      bytes += _text(
        encoded,
        styles: cols[i].styles,
        fromPx: fromPx,
        toPx: toPx,
      );
    }

    bytes += emptyLines(1);
    if (isNextRow) bytes += row(nextRow, columnGap: columnGap);

    return bytes;
  }

  /// Print image using ESC * (column format).
  /// Print image using ESC * (bit-image column format).
  ///
  /// If [maxWidth] or [maxHeight] is provided, the image is scaled down
  /// (preserving aspect ratio) so that it fits within the given bounds.
  List<int> printImage(
    Image imgSrc, {
    PrintAlign align = PrintAlign.center,
    bool isDoubleDensity = true,
    int? maxWidth,
    int? maxHeight,
  }) {
    List<int> bytes = [];
    bytes += setStyles(const TextStyles().copyWith(align: align));

    imgSrc = _constrainImage(imgSrc, maxWidth, maxHeight);

    final Image img;
    if (!isDoubleDensity) {
      final int size = paperSize.widthPixels ~/ 2;
      img = copyResize(
        imgSrc,
        width: size,
        interpolation: Interpolation.linear,
      );
    } else {
      img = Image.from(imgSrc);
    }

    invert(img);
    flipHorizontal(img);
    final Image rotated = copyRotate(img, angle: 270);

    final int lineHeight = isDoubleDensity ? 3 : 1;
    final List<List<int>> blobs = _toColumnFormat(rotated, lineHeight * 8);
    for (int i = 0; i < blobs.length; i++) {
      blobs[i] = _packBitsIntoBytes(blobs[i]);
    }

    final int heightPx = rotated.height;
    final int densityByte =
        (isDoubleDensity ? 1 : 0) + (isDoubleDensity ? 32 : 0);

    final List<int> header = List<int>.from(cBitImg.codeUnits)
      ..add(densityByte)
      ..addAll(_intLowHigh(heightPx, 2));

    // Adjust line spacing: ESC 3 0x00
    bytes += [27, 51, 0];
    for (final blob in blobs) {
      bytes += List<int>.from(header)
        ..addAll(blob)
        ..addAll('\n'.codeUnits);
    }

    // Reset line spacing: ESC 2
    bytes += [27, 50];
    return bytes;
  }

  /// Print image using GS v 0 (raster format, obsolete) or GS ( L (graphics).
  ///
  /// If [maxWidth] or [maxHeight] is provided, the image is scaled down
  /// (preserving aspect ratio) so that it fits within the given bounds.
  List<int> imageRaster(
    Image image, {
    PrintAlign align = PrintAlign.center,
    bool highDensityHorizontal = true,
    bool highDensityVertical = true,
    PrintImageMode imageMode = PrintImageMode.bitImageRaster,
    int? maxWidth,
    int? maxHeight,
  }) {
    List<int> bytes = [];
    bytes += setStyles(const TextStyles().copyWith(align: align));

    image = _constrainImage(image, maxWidth, maxHeight);

    final int widthPx = image.width;
    final int heightPx = image.height;
    final int widthBytes = (widthPx + 7) ~/ 8;
    final List<int> rasterData = _toRasterFormat(image);

    if (imageMode == PrintImageMode.bitImageRaster) {
      // GS v 0
      final int densityByte =
          (highDensityVertical ? 0 : 1) + (highDensityHorizontal ? 0 : 2);

      bytes += List<int>.from(cRasterImg2.codeUnits)
        ..add(densityByte)
        ..addAll(_intLowHigh(widthBytes, 2))
        ..addAll(_intLowHigh(heightPx, 2))
        ..addAll(rasterData);
    } else {
      // GS ( L — FN 112 (image data)
      final List<int> header1 = List<int>.from(cRasterImg.codeUnits)
        ..addAll(_intLowHigh(widthBytes * heightPx + 10, 2))
        ..addAll([48, 112, 48]) // m fn a
        ..addAll([1, 1]) // bx by
        ..add(49) // c
        ..addAll(_intLowHigh(widthBytes, 2))
        ..addAll(_intLowHigh(heightPx, 2))
        ..addAll(rasterData);

      bytes += header1;

      // GS ( L — FN 50 (run print)
      bytes += List<int>.from(cRasterImg.codeUnits)
        ..addAll([2, 0])
        ..addAll([48, 50]);
    }
    // LF — advance paper past the image and commit the print buffer.
    // This mirrors how text() always terminates with a newline, ensuring:
    //   • feed(n) reliably adds n visible blank lines after an image.
    //   • Consecutive imageRaster() calls print without the second being dropped.
    bytes += [10];
    return bytes;
  }

  /// Print a barcode.
  ///
  /// [data] is the barcode content as a plain string.
  /// [type] selects the barcode symbology.
  /// [width] units are printer-model dependent (typically 1–5).
  /// [height] range: 1–255 dots.
  List<int> barcode(
    String data, {
    BarcodeType type = BarcodeType.code128,
    int? width,
    int? height,
    BarcodeTextFont? textFont,
    BarcodeTextPosition textPosition = BarcodeTextPosition.below,
    PrintAlign align = PrintAlign.center,
  }) {
    final barcodeData = Barcode.encode(type, data);

    List<int> bytes = [];
    final List<int> header = cBarcodePrint.codeUnits + [type.value];

    bytes += setStyles(const TextStyles().copyWith(align: align));
    bytes += cBarcodeSelectPos.codeUnits + [textPosition.value];
    if (textFont != null) {
      bytes += cBarcodeSelectFont.codeUnits + [textFont.value];
    }
    if (width != null && width >= 0) {
      bytes += cBarcodeSetW.codeUnits + [width];
    }
    if (height != null && height >= 1 && height <= 255) {
      bytes += cBarcodeSetH.codeUnits + [height];
    }
    if (type.value <= 6) {
      bytes += header + barcodeData + [0]; // Function A
    } else {
      bytes += header + [barcodeData.length] + barcodeData; // Function B
    }
    return bytes;
  }

  /// Print a QR code using native printer encoding.
  List<int> qrcode(
    String text, {
    PrintAlign align = PrintAlign.center,
    QRSize size = QRSize.size4,
    QRCorrection cor = QRCorrection.L,
  }) {
    return [
      ...setStyles(const TextStyles().copyWith(align: align)),
      ...QRCode(text, size, cor).bytes,
    ];
  }

  /// Print the full character code table for debugging.
  List<int> printCodeTable({String? codeTable}) {
    List<int> bytes = [];
    bytes += cKanjiOff.codeUnits;

    if (codeTable != null) {
      bytes += Uint8List.fromList(
        List<int>.from(cCodeTable.codeUnits)
          ..add(profile.getCodePageId(codeTable)),
      );
    }

    bytes += List<int>.generate(256, (i) => i);
    return bytes;
  }

  /// Set print density / speech level (printer-model specific, 0–17 or 48–59).
  List<int> printSpeech(int level) {
    return List<int>.from(cControlHeader.codeUnits)
      ..addAll([0x02, 0x00, 0x32, level]);
  }

  /// Position + style + emit [textBytes].
  ///
  /// When [fromPx] is provided the print head is moved to that pixel position
  /// before the text. When [toPx] is also provided, right/center alignment is
  /// computed within the [fromPx]..[toPx] range.
  List<int> _text(
    Uint8List textBytes, {
    TextStyles styles = const TextStyles(),
    int? fromPx,
    int? toPx,
    int? maxCharsPerLine,
  }) {
    List<int> bytes = [];

    if (fromPx != null) {
      final charWidth = _getCharWidth(styles, maxCharsPerLine: maxCharsPerLine);
      double pos = fromPx.toDouble();

      if (toPx != null) {
        final textLen = textBytes.length * charWidth;
        if (styles.align == PrintAlign.right) {
          pos = toPx - textLen;
        } else if (styles.align == PrintAlign.center) {
          pos = fromPx + (toPx - fromPx) / 2 - textLen / 2;
        }
        if (pos < 0) pos = 0;
      }

      final String hexStr = pos.round().toRadixString(16).padLeft(3, '0');
      final List<int> hexPair = hex.decode(hexStr);

      bytes += Uint8List.fromList(
        List<int>.from(cPos.codeUnits)..addAll([hexPair[1], hexPair[0]]),
      );
    }

    bytes += setStyles(styles);
    bytes += textBytes;
    return bytes;
  }
}
