import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:unified_esc_pos_printer/unified_esc_pos_printer.dart';

void main() => runApp(const PrinterDemoApp());

class PrinterDemoApp extends StatelessWidget {
  const PrinterDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ESC/POS Printer Demo',
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
      ),
      home: const PrinterDemoPage(),
    );
  }
}

class PrinterDemoPage extends StatefulWidget {
  const PrinterDemoPage({super.key});

  @override
  State<PrinterDemoPage> createState() => _PrinterDemoPageState();
}

class _PrinterDemoPageState extends State<PrinterDemoPage> {
  final PrinterManager _manager = PrinterManager();
  final List<PrinterDevice> _devices = [];

  StreamSubscription<PrinterConnectionState>? _stateSub;
  StreamSubscription<List<PrinterDevice>>? _scanSub;

  PrinterConnectionState _state = PrinterConnectionState.disconnected;
  bool _scanning = false;

  /// Which connection types to scan. Null means scan all.
  PrinterConnectionType? _scanFilter;

  /// Which test parts to include when printing. All 6 by default.
  final Set<int> _selectedParts = {1, 2, 3, 4, 5, 6, 7};

  static const _partLabels = {
    1: 'Image & Text',
    2: 'Row & Columns',
    3: 'Multilingual',
    4: 'Text Raster',
    5: 'Raster Row & Columns',
    6: 'Barcodes',
    7: 'QR, Beep & Cashdrawer',
  };

  @override
  void initState() {
    super.initState();
    _stateSub = _manager.stateStream.listen((s) {
      if (mounted) setState(() => _state = s);
    });
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _scanSub?.cancel();
    _manager.dispose();
    super.dispose();
  }

  Future<void> _startScan() async {
    final Set<PrinterConnectionType> types = _scanFilter != null
        ? {_scanFilter!}
        : PrinterConnectionType.values.toSet();

    setState(() {
      _scanning = true;
      _devices.clear();
    });

    _scanSub?.cancel();
    _scanSub = _manager
        .scanAll(timeout: const Duration(seconds: 5), types: types)
        .listen(
      (devices) {
        if (mounted) {
          setState(() {
            _devices.clear();
            _devices.addAll(devices);
          });
        }
      },
      onDone: () {
        if (mounted) setState(() => _scanning = false);
      },
      onError: (_) {
        if (mounted) setState(() => _scanning = false);
      },
    );
  }

  Future<void> _connectTo(PrinterDevice device) async {
    try {
      await _manager.connect(device);
      _showSnack('Connected to ${device.name}');
    } on PrinterException catch (e) {
      _showSnack('Connection failed: ${e.message}');
    }
  }

  Future<void> _disconnect() async {
    await _manager.disconnect();
    _showSnack('Disconnected');
  }

  Future<void> _printTestTicket() async {
    if (_state != PrinterConnectionState.connected) {
      _showSnack('No printer connected');
      return;
    }

    try {
      final ticket = await Ticket.create(PaperSize.mm80);

      if (_selectedParts.contains(1)) await _addPart1(ticket);
      if (_selectedParts.contains(2)) _addPart2(ticket);
      if (_selectedParts.contains(3)) await _addPart3(ticket);
      if (_selectedParts.contains(4)) await _addPart4(ticket);
      if (_selectedParts.contains(5)) await _addPart5(ticket);
      if (_selectedParts.contains(6)) _addPart6(ticket);
      if (_selectedParts.contains(7)) _addPart7(ticket);

      _addFooter(ticket);
      ticket.cut();

      await _manager.printTicket(ticket);
      _showSnack('Ticket printed!');
    } on PrinterException catch (e) {
      _showSnack('Print failed: ${e.message}');
    }
  }

  // PART 1: Image, Title, Text Styles, Sizes, Alignment, Fonts
  Future<void> _addPart1(Ticket ticket) async {
    final byteData = await rootBundle.load('assets/flutter_bnw.png');
    final banner = img.decodeImage(byteData.buffer.asUint8List())!;
    ticket.imageRaster(
      banner,
      align: PrintAlign.center,
      maxWidth: 400,
      maxHeight: 200,
    );

    ticket.emptyLines();

    ticket.text(
      'CAPABILITY DEMO',
      align: PrintAlign.center,
      style: const PrintTextStyle(
        bold: true,
        height: TextSize.size2,
        width: TextSize.size2,
      ),
    );
    ticket.text(
      'unified_esc_pos_printer',
      align: PrintAlign.center,
      style: const PrintTextStyle(bold: true),
    );

    ticket.separator(char: '=');

    ticket.text(
      'TEXT STYLES',
      align: PrintAlign.center,
      style: const PrintTextStyle(
        bold: true,
        underline: true,
      ),
    );

    ticket.emptyLines();

    ticket.text('Normal text');
    ticket.text(
      'Bold text',
      style: const PrintTextStyle(bold: true),
    );
    ticket.text(
      'Underline text',
      style: const PrintTextStyle(underline: true),
    );
    ticket.text(
      'Reverse text',
      style: const PrintTextStyle(reverse: true),
    );
    ticket.text(
      'Bold + Underline',
      style: const PrintTextStyle(bold: true, underline: true),
    );

    ticket.emptyLines();

    ticket.text(
      'SIZE VARIATIONS',
      align: PrintAlign.center,
      style: const PrintTextStyle(bold: true),
    );
    ticket.text(
      'Size 1 (default)',
      style:
          const PrintTextStyle(height: TextSize.size1, width: TextSize.size1),
    );
    ticket.text(
      'Size 2',
      style:
          const PrintTextStyle(height: TextSize.size2, width: TextSize.size2),
    );
    ticket.text(
      'Size 3',
      style:
          const PrintTextStyle(height: TextSize.size3, width: TextSize.size3),
    );
    ticket.text(
      'Tall only',
      style:
          const PrintTextStyle(height: TextSize.size3, width: TextSize.size1),
    );
    ticket.text(
      'Wide only',
      style:
          const PrintTextStyle(height: TextSize.size1, width: TextSize.size3),
    );

    ticket.emptyLines();

    ticket.text(
      'ALIGNMENT',
      align: PrintAlign.center,
      style: const PrintTextStyle(bold: true),
    );
    ticket.text(
      'Left aligned',
      align: PrintAlign.left,
    );
    ticket.text(
      'Center aligned',
      align: PrintAlign.center,
    );
    ticket.text(
      'Right aligned',
      align: PrintAlign.right,
    );
    ticket.emptyLines();

    ticket.text(
      'FONT TYPES',
      align: PrintAlign.center,
      style: const PrintTextStyle(bold: true),
    );
    ticket.text(
      'Font A (default)',
      style: const PrintTextStyle(fontType: FontType.fontA),
    );
    ticket.text(
      'Font B (smaller)',
      style: const PrintTextStyle(fontType: FontType.fontB),
    );

    ticket.emptyLines();
  }

  // PART 2: Separators, 2-col, 3-col, 4-col Tables
  void _addPart2(Ticket ticket) {
    ticket.text(
      'SEPARATORS',
      align: PrintAlign.center,
      style: const PrintTextStyle(bold: true),
    );
    ticket.separator();
    ticket.separator(char: '=');
    ticket.separator(char: '*');
    ticket.separator(char: '~');

    ticket.emptyLines();

    ticket.text(
      '2-COLUMN TABLE',
      align: PrintAlign.center,
      style: const PrintTextStyle(bold: true),
    );
    ticket.separator();
    ticket.row([
      PrintColumn(
        text: 'Item',
        flex: 2,
        style: const PrintTextStyle(bold: true),
      ),
      PrintColumn(
        text: 'Price',
        flex: 1,
        align: PrintAlign.right,
        style: const PrintTextStyle(bold: true),
      ),
    ]);
    ticket.separator();
    ticket.row([
      PrintColumn(
        text: 'Espresso',
        flex: 2,
      ),
      PrintColumn(
        text: '\$3.50',
        flex: 1,
        align: PrintAlign.right,
      ),
    ]);
    ticket.row([
      PrintColumn(
        text: 'Cappuccino',
        flex: 2,
      ),
      PrintColumn(
        text: '\$4.25',
        flex: 1,
        align: PrintAlign.right,
      ),
    ]);
    ticket.row([
      PrintColumn(
        text: 'Latte Macchiato',
        flex: 2,
      ),
      PrintColumn(
        text: '\$4.75',
        flex: 1,
        align: PrintAlign.right,
      ),
    ]);
    ticket.separator();
    ticket.row([
      PrintColumn(
        text: 'TOTAL',
        flex: 2,
        style: const PrintTextStyle(bold: true),
      ),
      PrintColumn(
        text: '\$12.50',
        flex: 1,
        align: PrintAlign.right,
        style: const PrintTextStyle(bold: true),
      ),
    ]);

    ticket.emptyLines();

    ticket.text(
      '3-COLUMN TABLE',
      align: PrintAlign.center,
      style: const PrintTextStyle(bold: true),
    );
    ticket.separator();
    ticket.row([
      PrintColumn(
        text: 'Item',
        flex: 5,
        style: const PrintTextStyle(bold: true),
      ),
      PrintColumn(
        text: 'Qty',
        flex: 3,
        align: PrintAlign.center,
        style: const PrintTextStyle(bold: true),
      ),
      PrintColumn(
        text: 'Total',
        flex: 4,
        align: PrintAlign.right,
        style: const PrintTextStyle(bold: true),
      ),
    ]);
    ticket.separator();
    ticket.row([
      PrintColumn(
        text: 'Apple',
        flex: 5,
      ),
      PrintColumn(
        text: 'x3',
        flex: 3,
        align: PrintAlign.center,
      ),
      PrintColumn(
        text: '\$2.97',
        flex: 4,
        align: PrintAlign.right,
      ),
    ]);
    ticket.row([
      PrintColumn(
        text: 'Banana',
        flex: 5,
      ),
      PrintColumn(
        text: 'x6',
        flex: 3,
        align: PrintAlign.center,
      ),
      PrintColumn(
        text: '\$1.50',
        flex: 4,
        align: PrintAlign.right,
      ),
    ]);
    ticket.row([
      PrintColumn(
        text: 'Orange',
        flex: 5,
      ),
      PrintColumn(
        text: 'x2',
        flex: 3,
        align: PrintAlign.center,
      ),
      PrintColumn(
        text: '\$3.98',
        flex: 4,
        align: PrintAlign.right,
      ),
    ]);
    ticket.separator();
    ticket.row([
      PrintColumn(
        text: 'Grand Total',
        flex: 2,
        style: const PrintTextStyle(bold: true),
      ),
      PrintColumn(
        text: '\$8.45',
        flex: 1,
        align: PrintAlign.right,
        style: const PrintTextStyle(bold: true),
      ),
    ]);

    ticket.emptyLines();

    ticket.text(
      '4-COLUMN TABLE',
      align: PrintAlign.center,
      style: const PrintTextStyle(bold: true),
    );
    ticket.separator();
    ticket.row([
      PrintColumn(
        text: '#',
        flex: 1,
        style: const PrintTextStyle(bold: true),
      ),
      PrintColumn(
        text: 'Name',
        flex: 5,
        style: const PrintTextStyle(bold: true),
      ),
      PrintColumn(
        text: 'Qty',
        flex: 2,
        align: PrintAlign.center,
        style: const PrintTextStyle(bold: true),
      ),
      PrintColumn(
        text: 'Price',
        flex: 4,
        align: PrintAlign.right,
        style: const PrintTextStyle(bold: true),
      ),
    ]);
    ticket.separator();
    ticket.row([
      PrintColumn(
        text: '1',
        flex: 1,
      ),
      PrintColumn(
        text: 'Widget',
        flex: 5,
      ),
      PrintColumn(
        text: '10',
        flex: 2,
        align: PrintAlign.center,
      ),
      PrintColumn(
        text: '\$99.90',
        flex: 4,
        align: PrintAlign.right,
      ),
    ]);
    ticket.row([
      PrintColumn(
        text: '2',
        flex: 1,
      ),
      PrintColumn(
        text: 'Lorem ipsum dolor sit amet, consectetur adipiscing elit.',
        flex: 5,
      ),
      PrintColumn(
        text: '5',
        flex: 2,
        align: PrintAlign.center,
      ),
      PrintColumn(
        text: '\$74.95',
        flex: 4,
        align: PrintAlign.right,
      ),
    ]);
    ticket.row([
      PrintColumn(
        text: '3',
        flex: 1,
      ),
      PrintColumn(
        text: 'Fidget',
        flex: 5,
      ),
      PrintColumn(
        text: '5',
        flex: 2,
        align: PrintAlign.center,
      ),
      PrintColumn(
        text: '\$74.95',
        flex: 4,
        align: PrintAlign.right,
      ),
    ]);
    ticket.separator();

    ticket.emptyLines();
  }

  // PART 3: Multilingual Text
  Future<void> _addPart3(Ticket ticket) async {
    ticket.text(
      'MULTILINGUAL TEXT',
      align: PrintAlign.center,
      style: const PrintTextStyle(bold: true),
    );
    ticket.separator();

    ticket.text('Chinese:', style: const PrintTextStyle(bold: true));
    await ticket.textRaster('欢迎光临，谢谢惠顾！');
    await ticket.textRaster('恭喜发财');

    ticket.emptyLines();

    ticket.text('Japanese:', style: const PrintTextStyle(bold: true));
    await ticket.textRaster('ようこそ、ありがとう！');
    await ticket.textRaster('東山奈央はこの世界で一番かわいい');

    ticket.emptyLines();

    ticket.text('Javanese:', style: const PrintTextStyle(bold: true));
    await ticket.textRaster('Sꦈꦒꦺꦤ꧀ꦒ꧀ ꦫwꦈꦲ꧀, ꦩꦠꦸꦂ ꦤꦸwꦈꦤ꧀!');
    await ticket.textRaster('ꦗwꦄ ꦄꦢꦭꦲ꧀ ꦏꦺꦴꦌꦤ꧀ꦠ꧀ꦗꦶ');

    ticket.emptyLines();

    ticket.text('Korean:', style: const PrintTextStyle(bold: true));
    await ticket.textRaster('환영합니다, 감사합니다!');
    await ticket.textRaster('최신 한국 드라마를 알려주세요');

    ticket.emptyLines();

    ticket.text('Arabic:', style: const PrintTextStyle(bold: true));
    await ticket.textRaster(
      'سلامت داتڠ، تريما کاسيه!',
      textDirection: TextDirection.rtl,
    );
    await ticket.textRaster(
      'ستي حلال براذر',
      textDirection: TextDirection.rtl,
    );

    ticket.emptyLines();

    ticket.text('Hindi:', style: const PrintTextStyle(bold: true));
    await ticket.textRaster('स्वागत है, धन्यवाद!');
    await ticket.textRaster('चला छैया छैया छैया');

    ticket.emptyLines();

    ticket.text('Thai:', style: const PrintTextStyle(bold: true));
    await ticket.textRaster('ยินดีต้อนรับ ขอบคุณ!');
    await ticket.textRaster('เช็กว่ายังออริและไม่แก้ไข');

    ticket.emptyLines();

    ticket.text('Russian:', style: const PrintTextStyle(bold: true));
    await ticket.textRaster('Добро пожаловать, спасибо!');
    await ticket.textRaster('За Родину Урааааа!');

    ticket.emptyLines();

    ticket.text('European:', style: const PrintTextStyle(bold: true));
    await ticket.textRaster('French: Bienvenue, merci à bientôt !');
    await ticket.textRaster('German: Willkommen, vielen Dank!');
    await ticket.textRaster('Spanish: ¡Bienvenidos, muchas gracias señor!');
    await ticket.textRaster('Portuguese: Bem-vindos, muito obrigado a você!');

    ticket.emptyLines();
  }

  // PART 4: Text Raster Styles
  Future<void> _addPart4(Ticket ticket) async {
    ticket.text(
      'TEXT RASTER STYLES',
      align: PrintAlign.center,
      style: const PrintTextStyle(bold: true),
    );
    ticket.separator();

    ticket.text('Default (24 pt):', style: const PrintTextStyle(bold: true));
    await ticket.textRaster('欢迎光临 · Welcome · Bienvenido');

    ticket.emptyLines();

    ticket.text('Large (36 pt):', style: const PrintTextStyle(bold: true));
    await ticket.textRaster(
      '大きな文字 · 큰 글꼴',
      style: const TextStyle(fontSize: 36),
    );

    ticket.emptyLines();

    ticket.text('Bold:', style: const PrintTextStyle(bold: true));
    await ticket.textRaster(
      'Bold — Gras — Negrita — 굵게',
      style: const TextStyle(fontWeight: FontWeight.bold),
    );

    ticket.emptyLines();

    ticket.text('Italic:', style: const PrintTextStyle(bold: true));
    await ticket.textRaster(
      'Italic — Cursiva — 이탤릭',
      style: const TextStyle(fontStyle: FontStyle.italic),
    );

    ticket.emptyLines();

    ticket.text('Bold + Italic:', style: const PrintTextStyle(bold: true));
    await ticket.textRaster(
      'Bold Italic — بولد إيطاليك',
      style: const TextStyle(
        fontWeight: FontWeight.bold,
        fontStyle: FontStyle.italic,
      ),
    );

    ticket.emptyLines();

    ticket.text('Underline:', style: const PrintTextStyle(bold: true));
    await ticket.textRaster(
      'Underline · 밑줄 · 下線',
      style: const TextStyle(decoration: TextDecoration.underline),
    );

    ticket.emptyLines();

    ticket.text('Small (18 pt):', style: const PrintTextStyle(bold: true));
    await ticket.textRaster(
      'Small text — Petit texte — 소문자',
      style: const TextStyle(fontSize: 18),
    );

    ticket.emptyLines();

    ticket.text('Letter spacing:', style: const PrintTextStyle(bold: true));
    await ticket.textRaster(
      'S P A C E D',
      style: const TextStyle(letterSpacing: 6),
    );

    ticket.emptyLines();

    ticket.text('Center aligned:', style: const PrintTextStyle(bold: true));
    await ticket.textRaster(
      '가운데 정렬 · Centré · 居中',
      align: PrintAlign.center,
    );

    ticket.emptyLines();

    ticket.text('Right aligned:', style: const PrintTextStyle(bold: true));
    await ticket.textRaster(
      'Right · Droite · 右揃え',
      align: PrintAlign.right,
    );

    ticket.emptyLines();

    ticket.text('RTL bold (Arabic):', style: const PrintTextStyle(bold: true));
    await ticket.textRaster(
      'مرحبا — نص عريض كبير',
      style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
      textDirection: TextDirection.rtl,
      align: PrintAlign.right,
    );

    ticket.emptyLines();
  }

  // PART 6: Barcodes
  void _addPart6(Ticket ticket) {
    ticket.text(
      'BARCODES',
      align: PrintAlign.center,
      style: const PrintTextStyle(bold: true),
    );
    ticket.separator();

    ticket.text('EAN-13:', style: const PrintTextStyle(bold: true));
    ticket.barcode(
      '590123412345',
      type: BarcodeType.ean13,
      textPosition: BarcodeTextPosition.below,
    );

    ticket.emptyLines();

    ticket.text('EAN-8:', style: const PrintTextStyle(bold: true));
    ticket.barcode(
      '9031101',
      type: BarcodeType.ean8,
      textPosition: BarcodeTextPosition.below,
    );

    ticket.emptyLines();

    ticket.text('UPC-A:', style: const PrintTextStyle(bold: true));
    ticket.barcode(
      '01234567890',
      type: BarcodeType.upcA,
      textPosition: BarcodeTextPosition.below,
    );

    ticket.emptyLines();

    ticket.text('CODE 128:', style: const PrintTextStyle(bold: true));
    ticket.barcode(
      '{BABCDEF12345',
      type: BarcodeType.code128,
      textPosition: BarcodeTextPosition.below,
    );

    ticket.emptyLines();

    ticket.text('CODE 39:', style: const PrintTextStyle(bold: true));
    ticket.barcode(
      'HELLO123',
      type: BarcodeType.code39,
      textPosition: BarcodeTextPosition.below,
    );

    ticket.emptyLines();
  }

  // PART 7: QR Codes, Raster Images, Beep
  void _addPart7(Ticket ticket) {
    ticket.text(
      'QR CODES',
      align: PrintAlign.center,
      style: const PrintTextStyle(bold: true),
    );
    ticket.separator();

    ticket.text('Small (size 3):', style: const PrintTextStyle(bold: true));
    ticket.qrcode('https://pub.dev', size: QRSize.size3);

    ticket.emptyLines();

    ticket.text('Medium (size 5):', style: const PrintTextStyle(bold: true));
    ticket.qrcode('https://pub.dev', size: QRSize.size5);

    ticket.emptyLines();

    ticket.text('Large (size 8):', style: const PrintTextStyle(bold: true));
    ticket.qrcode('https://pub.dev', size: QRSize.size8, cor: QRCorrection.H);

    ticket.emptyLines();

    ticket.text(
      'RASTER IMAGE',
      align: PrintAlign.center,
      style: const PrintTextStyle(bold: true),
    );
    ticket.separator();

    final checker = img.Image(width: 160, height: 40);
    img.fill(checker, color: img.ColorRgb8(255, 255, 255));
    for (int y = 0; y < 40; y += 8) {
      for (int x = 0; x < 160; x += 8) {
        if ((x ~/ 8 + y ~/ 8) % 2 == 0) {
          img.fillRect(checker,
              x1: x,
              y1: y,
              x2: x + 7,
              y2: y + 7,
              color: img.ColorRgb8(0, 0, 0));
        }
      }
    }
    ticket.imageRaster(checker, align: PrintAlign.center);

    ticket.emptyLines();

    final gradient = img.Image(width: 200, height: 20);
    for (int x = 0; x < 200; x++) {
      final v = (x * 255 ~/ 199).clamp(0, 255);
      for (int y = 0; y < 20; y++) {
        gradient.setPixelRgb(x, y, v, v, v);
      }
    }
    ticket.text(
      'Gradient (dithered):',
      align: PrintAlign.center,
    );
    ticket.imageRaster(gradient, align: PrintAlign.center);

    ticket.emptyLines();

    ticket.text(
      'BEEP TEST',
      align: PrintAlign.center,
      style: const PrintTextStyle(bold: true),
    );
    ticket.beep(n: 5, duration: BeepDuration.beep100ms);

    ticket.emptyLines();

    ticket.text(
      'OPEN CASH DRAWER TEST',
      align: PrintAlign.center,
      style: const PrintTextStyle(bold: true),
    );
    ticket.openCashDrawer();

    ticket.emptyLines();
  }

  // PART 5: Raster Row & Columns (Flutter TextStyle columns)
  Future<void> _addPart5(Ticket ticket) async {
    ticket.text(
      'RASTER ROW & COLUMNS',
      align: PrintAlign.center,
      style: const PrintTextStyle(bold: true),
    );
    ticket.separator();

    // Simple two-column layout
    await ticket.rowRaster([
      PrintRasterColumn(text: 'Item', flex: 2),
      PrintRasterColumn(text: 'Price', flex: 1, align: PrintAlign.right),
    ]);

    await ticket.rowRaster([
      PrintRasterColumn(text: 'Cappuccino', flex: 2),
      PrintRasterColumn(text: '\$4.50', flex: 1, align: PrintAlign.right),
    ]);

    await ticket.rowRaster([
      PrintRasterColumn(text: 'Croissant', flex: 2),
      PrintRasterColumn(text: '\$3.25', flex: 1, align: PrintAlign.right),
    ]);

    ticket.emptyLines();

    // Styled columns
    await ticket.rowRaster([
      PrintRasterColumn(
        text: 'Bold Title',
        flex: 1,
        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
      ),
      PrintRasterColumn(
        text: 'Normal',
        flex: 1,
        align: PrintAlign.right,
      ),
    ]);

    ticket.emptyLines();

    // Three-column layout
    await ticket.rowRaster([
      PrintRasterColumn(text: 'Left', flex: 1),
      PrintRasterColumn(text: 'Center', flex: 1, align: PrintAlign.center),
      PrintRasterColumn(text: 'Right', flex: 1, align: PrintAlign.right),
    ]);

    ticket.emptyLines();

    // Multilingual raster row
    await ticket.rowRaster([
      PrintRasterColumn(text: '商品名', flex: 2),
      PrintRasterColumn(text: '数量', flex: 1, align: PrintAlign.center),
      PrintRasterColumn(text: '价格', flex: 1, align: PrintAlign.right),
    ]);

    await ticket.rowRaster([
      PrintRasterColumn(text: '拿铁咖啡', flex: 2),
      PrintRasterColumn(text: 'x2', flex: 1, align: PrintAlign.center),
      PrintRasterColumn(text: '¥56.00', flex: 1, align: PrintAlign.right),
    ]);

    ticket.emptyLines();
  }

  void _addFooter(Ticket ticket) {
    ticket.separator(char: '=');
    ticket.text(
      'unified_esc_pos_printer',
      align: PrintAlign.center,
      style: const PrintTextStyle(bold: true),
    );
    ticket.text(
      'Capabilities Demonstrated!',
      align: PrintAlign.center,
    );
    ticket.text(
      DateTime.now().toString().substring(0, 19),
      align: PrintAlign.center,
    );
    ticket.separator(char: '=');
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
      );
  }

  IconData _iconFor(PrinterDevice device) {
    return switch (device) {
      NetworkPrinterDevice() => Icons.wifi,
      BlePrinterDevice() => Icons.bluetooth,
      BluetoothPrinterDevice() => Icons.bluetooth_audio,
      UsbPrinterDevice() => Icons.usb,
      _ => Icons.print,
    };
  }

  String _subtitleFor(PrinterDevice device) {
    return switch (device) {
      NetworkPrinterDevice(host: final h, port: final p) => 'TCP $h:$p',
      BlePrinterDevice(deviceId: final id) => 'BLE $id',
      BluetoothPrinterDevice(address: final addr) => 'BT $addr',
      UsbPrinterDevice(identifier: final id) => 'USB $id',
      _ => device.connectionType.name,
    };
  }

  String _filterLabel(PrinterConnectionType? filter) {
    if (filter == null) return 'All';
    return switch (filter) {
      PrinterConnectionType.network => 'Network',
      PrinterConnectionType.ble => 'BLE',
      PrinterConnectionType.bluetooth => 'Bluetooth',
      PrinterConnectionType.usb => 'USB',
    };
  }

  IconData _filterIcon(PrinterConnectionType? filter) {
    if (filter == null) return Icons.select_all;
    return switch (filter) {
      PrinterConnectionType.network => Icons.wifi,
      PrinterConnectionType.ble => Icons.bluetooth,
      PrinterConnectionType.bluetooth => Icons.bluetooth_audio,
      PrinterConnectionType.usb => Icons.usb,
    };
  }

  @override
  Widget build(BuildContext context) {
    final bool connected = _state == PrinterConnectionState.connected;
    final connectedDevice = _manager.connectedDevice;

    return Scaffold(
      appBar: AppBar(
        title: const Text('ESC/POS Printer Demo'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: _ConnectionStatusBar(
              state: _state,
              device: connectedDevice,
              onDisconnect: connected ? _disconnect : null,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _FilterChip(
                    label: 'All',
                    icon: Icons.select_all,
                    selected: _scanFilter == null,
                    onTap: () => setState(() => _scanFilter = null),
                  ),
                  for (final type in PrinterConnectionType.values)
                    _FilterChip(
                      label: _filterLabel(type),
                      icon: _filterIcon(type),
                      selected: _scanFilter == type,
                      onTap: () => setState(() => _scanFilter = type),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _scanning ? null : _startScan,
                icon: _scanning
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(_filterIcon(_scanFilter)),
                label: Text(
                  _scanning
                      ? 'Scanning ${_filterLabel(_scanFilter)}...'
                      : 'Scan ${_filterLabel(_scanFilter)}',
                ),
              ),
            ),
          ),
          Expanded(
            child: _devices.isEmpty
                ? Center(
                    child: Text(
                      _scanning
                          ? 'Searching for printers...'
                          : 'No printers found. Tap Scan.',
                    ),
                  )
                : ListView.builder(
                    itemCount: _devices.length,
                    itemBuilder: (context, i) {
                      final device = _devices[i];
                      final bool isActive = _manager.connectedDevice == device;
                      return ListTile(
                        leading: Icon(_iconFor(device)),
                        title: Text(
                          device.name,
                          style: TextStyle(
                            fontWeight:
                                isActive ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        subtitle: Text(_subtitleFor(device)),
                        trailing:
                            isActive ? const Icon(Icons.check_circle) : null,
                        selected: isActive,
                        selectedTileColor: Colors.grey.withValues(alpha: 0.1),
                        onTap: connected || _scanning
                            ? null
                            : () => _connectTo(device),
                      );
                    },
                  ),
          ),
          Container(
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 3,
                  offset: const Offset(0, -2),
                )
              ],
            ),
            child: Column(
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: FilterChip(
                          label: const Text('All'),
                          selected: _selectedParts.length == _partLabels.length,
                          onSelected: (_) => setState(() {
                            if (_selectedParts.length == _partLabels.length) {
                              _selectedParts.clear();
                            } else {
                              _selectedParts.addAll(_partLabels.keys);
                            }
                          }),
                        ),
                      ),
                      for (final entry in _partLabels.entries)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: FilterChip(
                            label: Text(entry.value),
                            selected: _selectedParts.contains(entry.key),
                            onSelected: (selected) => setState(() {
                              selected
                                  ? _selectedParts.add(entry.key)
                                  : _selectedParts.remove(entry.key);
                            }),
                          ),
                        ),
                    ],
                  ),
                ),
                SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _scanning || !connected || _selectedParts.isEmpty
                        ? null
                        : _printTestTicket,
                    icon: const Icon(Icons.receipt_long),
                    label: const Text('Print Test Ticket'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectionStatusBar extends StatelessWidget {
  const _ConnectionStatusBar({
    required this.state,
    required this.device,
    required this.onDisconnect,
  });

  final PrinterConnectionState state;
  final PrinterDevice? device;
  final VoidCallback? onDisconnect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool connected = state == PrinterConnectionState.connected;
    final bool connecting = state == PrinterConnectionState.connecting;
    final bool error = state == PrinterConnectionState.error;

    final Color bgColor;
    final Color fgColor;
    final IconData icon;
    final String label;

    if (connected) {
      bgColor = Colors.green.shade50;
      fgColor = Colors.green.shade800;
      icon = Icons.check_circle;
      label = device?.name ?? 'Connected';
    } else if (connecting) {
      bgColor = Colors.orange.shade50;
      fgColor = Colors.orange.shade800;
      icon = Icons.sensors_rounded;
      label = 'Connecting...';
    } else if (error) {
      bgColor = Colors.red.shade50;
      fgColor = Colors.red.shade800;
      icon = Icons.error;
      label = 'Connection error';
    } else {
      bgColor =
          theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5);
      fgColor = theme.colorScheme.onSurfaceVariant;
      icon = Icons.print_disabled;
      label = 'No printer connected';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: fgColor, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: fgColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (connected && device != null)
                  Text(
                    '${device!.connectionType.name.toUpperCase()} - ${_deviceDetail(device!)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: fgColor.withValues(alpha: 0.7),
                    ),
                  ),
              ],
            ),
          ),
          if (connected)
            TextButton(
              onPressed: onDisconnect,
              child: Text('Disconnect', style: TextStyle(color: fgColor)),
            ),
        ],
      ),
    );
  }

  String _deviceDetail(PrinterDevice device) {
    return switch (device) {
      NetworkPrinterDevice(host: final h, port: final p) => '$h:$p',
      BlePrinterDevice(deviceId: final id) => id,
      BluetoothPrinterDevice(address: final addr) => addr,
      UsbPrinterDevice(identifier: final id) => id,
      _ => '',
    };
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: FilterChip(
        showCheckmark: false,
        avatar: Icon(icon, size: 18),
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
      ),
    );
  }
}
