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
