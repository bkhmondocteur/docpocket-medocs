import 'package:flutter/services.dart';

typedef BarcodeScanCallback = void Function(String scannedBarcode);

/// Écouteur global pour douchettes code-barres USB en mode émulation clavier
/// Compatible Windows, macOS et Web (PWA) sans nécessiter de focus spécifique
class BarcodeHardwareListener {
  static final BarcodeHardwareListener instance = BarcodeHardwareListener._internal();
  BarcodeHardwareListener._internal();

  final List<BarcodeScanCallback> _listeners = [];
  final StringBuffer _buffer = StringBuffer();
  DateTime _lastKeystrokeTime = DateTime.now();

  // Seuil de détection en millisecondes entre deux frappes pour distinguer douchette vs frappe humaine
  static const int _barcodeMaxInterKeyMs = 80;

  bool _isListening = false;

  void startListening() {
    if (_isListening) return;
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    _isListening = true;
  }

  void stopListening() {
    if (!_isListening) return;
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    _isListening = false;
  }

  void addListener(BarcodeScanCallback callback) {
    if (!_listeners.contains(callback)) {
      _listeners.add(callback);
    }
  }

  void removeListener(BarcodeScanCallback callback) {
    _listeners.remove(callback);
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;

    final now = DateTime.now();
    final elapsed = now.difference(_lastKeystrokeTime).inMilliseconds;
    _lastKeystrokeTime = now;

    // Si le délai entre deux frappes est trop grand, ce n'est pas une douchette rapide, on vide le tampon
    if (elapsed > _barcodeMaxInterKeyMs && _buffer.isNotEmpty) {
      _buffer.clear();
    }

    final key = event.logicalKey;

    // Touche d'envoi final de la douchette USB (Enter / NumpadEnter)
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
      if (_buffer.isNotEmpty) {
        final scanned = _buffer.toString().trim();
        _buffer.clear();

        if (scanned.length >= 8) {
          _notifyListeners(scanned);
          return true; // Intercepte l'événement pour éviter les sauts de ligne intempestifs
        }
      }
      return false;
    }

    // Caractères imprimables reçus de la douchette
    final char = event.character;
    if (char != null && char.isNotEmpty) {
      _buffer.write(char);
    }

    return false;
  }

  void _notifyListeners(String barcode) {
    for (final listener in List.of(_listeners)) {
      try {
        listener(barcode);
      } catch (e) {
        // Ignorer les erreurs d'un listener pour ne pas bloquer les autres
      }
    }
  }
}
