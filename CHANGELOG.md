## 3.3.2

- Allow Bluetooth scan/connect from a background isolate (e.g. a Firebase Messaging background handler or WorkManager) when the required permissions were already granted in a prior foreground session ([#12](https://github.com/elrizwiraswara/unified_esc_pos_printer/issues/12)). The native permission handler previously returned `false` whenever no `Activity` was attached, which is always the case in a background isolate, so every `scan()`/`connect()` threw a permission error even though the OS permissions were granted. It now checks already-granted permissions against the application context (which needs no `Activity`) and only requires an `Activity` to *prompt* for missing ones. Background isolates still cannot show a permission prompt, and Bluetooth discovery remains unreliable there, so connect to a known device by address rather than scanning.

## 3.3.1

- Fix `Ticket.row()` / `Generator.row()` printing each column on its own line on many generic ESC/POS printers ([#10](https://github.com/elrizwiraswara/unified_esc_pos_printer/issues/10)). Each column was preceded by its own `ESC a` (select justification) command. Per the ESC/POS specification `ESC a` is only honoured at the beginning of a line, and many clone printers respond to a mid-line `ESC a` by flushing the buffered line and feeding — pushing every column onto a separate line. Column alignment is already achieved by the absolute print position (`ESC $`), so `ESC a` is now emitted only once per row (left justification, at the start of the line) and never per column. Output is unchanged on printers that previously rendered rows correctly.

## 3.3.0

- Add native Android support for USB Printer Class (interface class `0x07`) devices ([#5](https://github.com/elrizwiraswara/unified_esc_pos_printer/issues/5), [#8](https://github.com/elrizwiraswara/unified_esc_pos_printer/issues/8)). Most generic ESC/POS thermal printers expose this class instead of a CDC / serial chip and previously failed with `Not an Serial device` from the `usb_serial` package. The connector now probes each device's USB interface classes and routes Printer Class devices through a new native `UsbManager` + `bulkTransfer` path while keeping the existing `usb_serial` path for CDC / Virtual COM devices (FTDI, CP210x, PL2303, CH34x, USB CDC ACM). The user sees a one-time Android USB permission dialog on first connect to a Printer Class device.

## 3.2.1

- Remove hardcoded permissions from the package's Android manifest. The library no longer declares `BLUETOOTH`, `BLUETOOTH_ADMIN`, `BLUETOOTH_SCAN`, `BLUETOOTH_CONNECT`, `ACCESS_FINE_LOCATION`, or `ACCESS_COARSE_LOCATION` — these previously included `maxSdkVersion="30"` on the location entries, which the Android manifest merger propagated into consuming apps and broke apps that need location permissions on API 31+ for other features (maps, geolocation, etc.). Consumers must now declare the permissions they need in their own `AndroidManifest.xml`; see the updated "Android Setup" section in the README for the recommended permission set.

## 3.2.0

- Migrate USB serial dependency from `flutter_libserialport` to `libserialport_plus` to fix Android 16KB page size compatibility ([#3](https://github.com/elrizwiraswara/unified_esc_pos_printer/pull/3))

## 3.1.0

- Add `PrintRasterColumn` class for Flutter `TextStyle`-based column definitions
- Add `Ticket.rowRaster()` method for raster-rendered table rows with full Flutter text styling, multilingual support, and RTL text direction
- Update example app with Raster Row & Columns demo

## 3.0.1

- Fix iOS BLE scan stream handler by using explicit `BleScanStreamHandler` when setting the stream handler for the BLE scan event channel ([#1](https://github.com/elrizwiraswara/unified_esc_pos_printer/issues/1))

## 3.0.0

- BREAKING: Rename `TextStyles` to `PrintTextStyle`
- BREAKING: Rename `styles` parameter to `style` in ticket/generator APIs and `PrintColumn`
- BREAKING: Rename `textStyle` to `style` in `Ticket.textRaster(...)` and `renderTextLinesAsImages(...)`
- Update README and example app to use the new names

## 2.0.0

- BREAKING: Remove `align` from `TextStyles`
- Add explicit `align` parameter to `Ticket.text(...)` and `Ticket.textEncoded(...)`
- Add `PrintColumn.align` for row/column alignment
- Update `Generator` alignment flow to use explicit alignment parameters
- Update `README.md` and example app usage to the new alignment API

## 1.0.3

- Rename `spaceBetweenRows` to `columnGap` for clarity
- Only apply `columnGap` between columns, not after the last column
- Change default `columnGap` from 5 to 1

## 1.0.2

- Improved Pub Score

## 1.0.1

- Update README.md.

## 1.0.0

- Initial release.
