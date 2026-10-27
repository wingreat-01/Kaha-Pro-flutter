import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Listens for USB / Bluetooth barcode scanners.
///
/// Almost every handheld scanner works as a "keyboard wedge": it types
/// the barcode's characters extremely fast and finishes with Enter. This
/// widget watches hardware key events and, when a burst of characters
/// (each arriving within [maxGap] of the last) ends with Enter and is at
/// least [minLength] long, calls [onBarcode] with the code.
///
/// It deliberately stays out of the way:
///  - key events are never consumed (the handler always returns false);
///  - bursts are ignored while a text field has focus, so scanning into
///    a field (e.g. the Barcode field of the add-product dialog) just
///    types into it as usual;
///  - bursts are ignored unless this screen's route is the current one,
///    so a scan can't ring up an item behind an open dialog/checkout.
class BarcodeKeyboardListener extends StatefulWidget {
  final bool enabled;
  final ValueChanged<String> onBarcode;
  final int minLength;
  final Duration maxGap;
  final Widget child;

  const BarcodeKeyboardListener({
    super.key,
    required this.enabled,
    required this.onBarcode,
    required this.child,
    this.minLength = 4,
    this.maxGap = const Duration(milliseconds: 100),
  });

  @override
  State<BarcodeKeyboardListener> createState() => _BarcodeKeyboardListenerState();
}

class _BarcodeKeyboardListenerState extends State<BarcodeKeyboardListener> {
  static const int _maxCodeLength = 64;

  final StringBuffer _buffer = StringBuffer();
  DateTime? _lastKeyAt;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _textFieldHasFocus() {
    final focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext == null) return false;
    return focusContext.widget is EditableText ||
        focusContext.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  bool _onKey(KeyEvent event) {
    if (!widget.enabled || event is! KeyDownEvent) return false;

    final now = DateTime.now();
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
      final code = _buffer.toString();
      _buffer.clear();
      _lastKeyAt = null;
      if (code.length >= widget.minLength &&
          mounted &&
          (ModalRoute.of(context)?.isCurrent ?? true) &&
          !_textFieldHasFocus()) {
        widget.onBarcode(code);
      }
      return false;
    }

    final ch = event.character;
    if (ch == null || ch.isEmpty || ch.runes.length != 1) return false;

    final last = _lastKeyAt;
    if (last != null && now.difference(last) > widget.maxGap) {
      _buffer.clear();
    }
    if (_buffer.length < _maxCodeLength) _buffer.write(ch);
    _lastKeyAt = now;
    return false;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
