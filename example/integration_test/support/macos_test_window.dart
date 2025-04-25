import 'dart:ffi';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart' show setUpAll, tearDownAll;

/// Keeps the macOS test window on screen for every test of a file. Flutter draws no frame while its window is off
/// screen (app hidden, window on another Space, for instance when an iOS simulator run activates Simulator.app in
/// a full-screen Space), so every `pump` blocks until it shows again; `flutter test` also often fails to foreground
/// the app ("Failed to foreground app"). A window merely covered by other windows keeps drawing.
///
/// Calls AppKit through the Objective-C runtime from Dart, which runs on the platform thread (merged threads).
void holdMacOSTestWindowInFront() {
  if (!Platform.isMacOS) return;
  final window = _MacOSTestWindow();
  setUpAll(() {
    debugPrint('[window] visible before activation: ${window.visible}');
    window.keepInFront();
  });
  tearDownAll(window.restoreLevel);
}

class _MacOSTestWindow {
  final _lib = DynamicLibrary.process();
  late final _getClass = _lib
      .lookupFunction<Pointer<Void> Function(Pointer<Uint8>), Pointer<Void> Function(Pointer<Uint8>)>('objc_getClass');
  late final _registerName = _lib
      .lookupFunction<Pointer<Void> Function(Pointer<Uint8>), Pointer<Void> Function(Pointer<Uint8>)>(
        'sel_registerName',
      );
  late final _malloc = _lib.lookupFunction<Pointer<Uint8> Function(Size), Pointer<Uint8> Function(int)>('malloc');
  late final _free = _lib.lookupFunction<Void Function(Pointer<Uint8>), void Function(Pointer<Uint8>)>('free');
  late final _isMainThread = _lib.lookupFunction<Int32 Function(), int Function()>('pthread_main_np');
  late final _sendId = _lib
      .lookupFunction<
        Pointer<Void> Function(Pointer<Void>, Pointer<Void>),
        Pointer<Void> Function(Pointer<Void>, Pointer<Void>)
      >('objc_msgSend');
  late final _sendIdIndex = _lib
      .lookupFunction<
        Pointer<Void> Function(Pointer<Void>, Pointer<Void>, UnsignedLong),
        Pointer<Void> Function(Pointer<Void>, Pointer<Void>, int)
      >('objc_msgSend');
  late final _sendIdId = _lib
      .lookupFunction<
        Pointer<Void> Function(Pointer<Void>, Pointer<Void>, Pointer<Void>),
        Pointer<Void> Function(Pointer<Void>, Pointer<Void>, Pointer<Void>)
      >('objc_msgSend');
  late final _sendUnsigned = _lib
      .lookupFunction<UnsignedLong Function(Pointer<Void>, Pointer<Void>), int Function(Pointer<Void>, Pointer<Void>)>(
        'objc_msgSend',
      );
  late final _sendVoid = _lib
      .lookupFunction<Void Function(Pointer<Void>, Pointer<Void>), void Function(Pointer<Void>, Pointer<Void>)>(
        'objc_msgSend',
      );
  late final _sendVoidBool = _lib
      .lookupFunction<
        Void Function(Pointer<Void>, Pointer<Void>, Bool),
        void Function(Pointer<Void>, Pointer<Void>, bool)
      >('objc_msgSend');
  late final _sendVoidLong = _lib
      .lookupFunction<
        Void Function(Pointer<Void>, Pointer<Void>, Long),
        void Function(Pointer<Void>, Pointer<Void>, int)
      >('objc_msgSend');

  final _selectors = <String, Pointer<Void>>{};

  Pointer<Void> _cString(String value, Pointer<Void> Function(Pointer<Uint8>) body) {
    final bytes = value.codeUnits;
    final buffer = _malloc(bytes.length + 1);
    for (var i = 0; i < bytes.length; i++) {
      buffer[i] = bytes[i];
    }
    buffer[bytes.length] = 0;
    try {
      return body(buffer);
    } finally {
      _free(buffer);
    }
  }

  Pointer<Void> _sel(String name) => _selectors.putIfAbsent(name, () => _cString(name, _registerName));

  Pointer<Void> get _app => _sendId(_cString('NSApplication', _getClass), _sel('sharedApplication'));

  Pointer<Void> get _window {
    _checkThread();
    final windows = _sendId(_app, _sel('windows'));
    final count = _sendUnsigned(windows, _sel('count'));
    for (var i = 0; i < count; i++) {
      final window = _sendIdIndex(windows, _sel('objectAtIndex:'), i);
      if (_sendId(window, _sel('contentViewController')) != nullptr) return window;
    }
    throw StateError('no window with a content view controller');
  }

  void _checkThread() {
    if (_isMainThread() != 1) throw StateError('Dart does not run on the platform thread: AppKit unsafe here');
  }

  /// Whether any part of the window is on screen (`NSWindowOcclusionStateVisible`).
  bool get visible => _sendUnsigned(_window, _sel('occlusionState')) & 2 != 0;

  /// Unhides and activates the app, shows its window on every Space (also over a full-screen app) and above the
  /// windows of other apps (floating level).
  void keepInFront() {
    final window = _window;
    _sendIdId(_app, _sel('unhide:'), nullptr);
    _sendVoidBool(_app, _sel('activateIgnoringOtherApps:'), true);
    const canJoinAllSpaces = 1 << 0;
    const fullScreenAuxiliary = 1 << 8;
    _sendVoidLong(window, _sel('setCollectionBehavior:'), canJoinAllSpaces | fullScreenAuxiliary);
    _sendVoidLong(window, _sel('setLevel:'), 3);
    _sendIdId(window, _sel('makeKeyAndOrderFront:'), nullptr);
    _sendVoid(window, _sel('orderFrontRegardless'));
  }

  void restoreLevel() => _sendVoidLong(_window, _sel('setLevel:'), 0);
}
