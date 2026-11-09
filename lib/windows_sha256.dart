import 'dart:ffi';
import 'dart:io';

// Windows CNG owns the hash object; the process heap owns the I/O buffers.
class WindowsSha256 {
  WindowsSha256._() {
    try {
      _state = _allocate(32);
      _buffer = _allocate(1024 * 1024);
      final name = (_state + 16).cast<Uint16>();
      final algorithm = name.asTypedList(7);
      algorithm.setAll(0, 'SHA256'.codeUnits);
      _check(_api.open(_state.cast(), name, nullptr, 0));
      _algorithm = _state.cast<Pointer<Void>>().value;
      _check(_api.create(_algorithm, _state.cast(), nullptr, 0, nullptr, 0, 0));
      _hash = _state.cast<Pointer<Void>>().value;
    } catch (_) {
      close();
      rethrow;
    }
  }

  static WindowsSha256? tryCreate() {
    if (!Platform.isWindows) return null;
    try {
      return WindowsSha256._();
    } catch (_) {
      return null;
    }
  }

  static final _api = _Cng();
  Pointer<Void> _algorithm = nullptr, _hash = nullptr;
  Pointer<Uint8> _state = nullptr, _buffer = nullptr;
  bool _closed = false;

  Pointer<Uint8> _allocate(int bytes) {
    final pointer = _api.allocate(_api.heap(), 8, bytes);
    if (pointer == nullptr) {
      throw StateError('Windows hash buffer allocation failed');
    }
    return pointer.cast();
  }

  void _check(int status) {
    if (status < 0) {
      throw StateError(
        'Windows SHA-256 failed (${status.toUnsigned(32).toRadixString(16)})',
      );
    }
  }

  void add(List<int> bytes) {
    if (_closed) throw StateError('Hash has already been closed');
    final buffer = _buffer.asTypedList(1024 * 1024);
    for (var offset = 0; offset < bytes.length;) {
      final length = (bytes.length - offset).clamp(0, buffer.length);
      buffer.setRange(0, length, bytes, offset);
      _check(_api.update(_hash, _buffer, length, 0));
      offset += length;
    }
  }

  String finish() {
    if (_closed) throw StateError('Hash has already been closed');
    try {
      _check(_api.finish(_hash, _state, 32, 0));
      return _state
          .asTypedList(32)
          .map((value) => value.toRadixString(16).padLeft(2, '0'))
          .join();
    } finally {
      close();
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    if (_hash != nullptr) _api.destroy(_hash);
    if (_algorithm != nullptr) _api.closeAlgorithm(_algorithm, 0);
    if (_buffer != nullptr) _api.free(_api.heap(), 0, _buffer.cast());
    if (_state != nullptr) _api.free(_api.heap(), 0, _state.cast());
  }
}

class _Cng {
  final bcrypt = DynamicLibrary.open('bcrypt.dll');
  final kernel = DynamicLibrary.open('kernel32.dll');
  late final heap = kernel
      .lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
        'GetProcessHeap',
      );
  late final allocate = kernel
      .lookupFunction<
        Pointer<Void> Function(Pointer<Void>, Uint32, UintPtr),
        Pointer<Void> Function(Pointer<Void>, int, int)
      >('HeapAlloc');
  late final free = kernel
      .lookupFunction<
        Int32 Function(Pointer<Void>, Uint32, Pointer<Void>),
        int Function(Pointer<Void>, int, Pointer<Void>)
      >('HeapFree');
  late final open = bcrypt
      .lookupFunction<
        Int32 Function(
          Pointer<Pointer<Void>>,
          Pointer<Uint16>,
          Pointer<Uint16>,
          Uint32,
        ),
        int Function(
          Pointer<Pointer<Void>>,
          Pointer<Uint16>,
          Pointer<Uint16>,
          int,
        )
      >('BCryptOpenAlgorithmProvider');
  late final create = bcrypt
      .lookupFunction<
        Int32 Function(
          Pointer<Void>,
          Pointer<Pointer<Void>>,
          Pointer<Uint8>,
          Uint32,
          Pointer<Uint8>,
          Uint32,
          Uint32,
        ),
        int Function(
          Pointer<Void>,
          Pointer<Pointer<Void>>,
          Pointer<Uint8>,
          int,
          Pointer<Uint8>,
          int,
          int,
        )
      >('BCryptCreateHash');
  late final update = bcrypt
      .lookupFunction<
        Int32 Function(Pointer<Void>, Pointer<Uint8>, Uint32, Uint32),
        int Function(Pointer<Void>, Pointer<Uint8>, int, int)
      >('BCryptHashData');
  late final finish = bcrypt
      .lookupFunction<
        Int32 Function(Pointer<Void>, Pointer<Uint8>, Uint32, Uint32),
        int Function(Pointer<Void>, Pointer<Uint8>, int, int)
      >('BCryptFinishHash');
  late final destroy = bcrypt
      .lookupFunction<
        Int32 Function(Pointer<Void>),
        int Function(Pointer<Void>)
      >('BCryptDestroyHash');
  late final closeAlgorithm = bcrypt
      .lookupFunction<
        Int32 Function(Pointer<Void>, Uint32),
        int Function(Pointer<Void>, int)
      >('BCryptCloseAlgorithmProvider');
}
