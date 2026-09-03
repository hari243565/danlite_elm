import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

// ── Device model ─────────────────────────────────────────────────────────────
class BtDevice {
  final String name;
  final String address;
  final bool bonded;

  const BtDevice({
    required this.name,
    required this.address,
    this.bonded = false,
  });

  factory BtDevice.fromMap(Map<dynamic, dynamic> map) => BtDevice(
        name: map['name'] as String? ?? 'Unknown',
        address: map['address'] as String,
        bonded: map['bonded'] as bool? ?? false,
      );

  BtDevice copyWith({bool? bonded}) =>
      BtDevice(name: name, address: address, bonded: bonded ?? this.bonded);

  @override
  bool operator ==(Object other) =>
      other is BtDevice && other.address == address;

  @override
  int get hashCode => address.hashCode;
}

// ── Bond / scan / connection state ───────────────────────────────────────────
enum BtState { idle, scanning, bonding, connecting, connected, error }

// ── Service ───────────────────────────────────────────────────────────────────
class BluetoothClassicService extends ChangeNotifier {
  static const _method = MethodChannel('com.danlite.elm/bluetooth_classic');
  static const _dataEvents = EventChannel('com.danlite.elm/bluetooth_data');
  static const _discEvents =
      EventChannel('com.danlite.elm/bluetooth_discovery');

  // ── State ─────────────────────────────────────────────────────────────────
  BtState _state = BtState.idle;
  BtState get state => _state;

  String _statusMessage = 'Ready';
  String get statusMessage => _statusMessage;

  BtDevice? _connectedDevice;
  BtDevice? get connectedDevice => _connectedDevice;

  bool get isConnected => _state == BtState.connected;
  bool get isScanning => _state == BtState.scanning;
  bool get isConnecting =>
      _state == BtState.connecting || _state == BtState.bonding;

  final List<BtDevice> _bondedDevices = [];
  final List<BtDevice> _discoveredDevices = [];

  List<BtDevice> get bondedDevices => List.unmodifiable(_bondedDevices);
  List<BtDevice> get discoveredDevices => List.unmodifiable(_discoveredDevices);

  // ── Data stream ───────────────────────────────────────────────────────────
  final _dataCtrl = StreamController<String>.broadcast();
  Stream<String> get dataStream => _dataCtrl.stream;

  StreamSubscription<dynamic>? _discSub;
  StreamSubscription<dynamic>? _dataSub;

  // ── Permissions ───────────────────────────────────────────────────────────
  /// Cached `Build.VERSION.SDK_INT`. Read once — the OS version cannot change
  /// while the process is alive.
  static int? _sdkIntCache;

  /// The running device's Android API level.
  ///
  /// Falls back to 31 if device_info_plus cannot answer. That fallback is
  /// deliberate: 31+ is the branch that asks for the FEWEST permissions, so a
  /// failure here can never invent a new mandatory prompt that locks a working
  /// adapter out.
  static Future<int> _sdkInt() async {
    final cached = _sdkIntCache;
    if (cached != null) return cached;
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      return _sdkIntCache = info.version.sdkInt;
    } catch (_) {
      return _sdkIntCache = 31;
    }
  }

  /// Returns true if all required Bluetooth permissions are granted.
  ///
  /// ═══════════════════════════════════════════════════════════════════════
  /// LOAD-BEARING: *which* permissions are asked for depends on the API level,
  /// and asking for the wrong set is a total Bluetooth lockout, not a warning.
  ///
  /// Android 12 (API 31) split Bluetooth out of the location permission group.
  /// AndroidManifest.xml already reflects that split exactly — BLUETOOTH and
  /// BLUETOOTH_ADMIN are capped at `maxSdkVersion="30"`, and BLUETOOTH_SCAN is
  /// declared `neverForLocation` — so the two halves must never be mixed:
  ///
  ///   API >= 31 : BLUETOOTH_CONNECT + BLUETOOTH_SCAN are the runtime grants.
  ///               Location is NOT needed and is NOT requested. Asking for it
  ///               anyway put an unexplained "allow location?" prompt in front
  ///               of a mechanic connecting an OBD dongle, and a perfectly
  ///               reasonable "Don't allow" then failed the all-or-nothing
  ///               check below — leaving every screen rendering correctly with
  ///               no live data and no connection of any kind.
  ///
  ///   API <  31 : BLUETOOTH/BLUETOOTH_ADMIN are install-time grants, so there
  ///               is nothing to request for them — and BLUETOOTH_CONNECT /
  ///               BLUETOOTH_SCAN do not exist as runtime permissions on these
  ///               devices, so requesting them returns denied and would fail
  ///               the same check. Location genuinely IS required for
  ///               discovery here, so it is the only thing asked for.
  /// ═══════════════════════════════════════════════════════════════════════
  Future<bool> requestPermissions() async {
    if (defaultTargetPlatform != TargetPlatform.android) return true;

    final sdkInt = await _sdkInt();

    final toRequest = sdkInt >= 31
        ? <Permission>[Permission.bluetoothConnect, Permission.bluetoothScan]
        : <Permission>[Permission.locationWhenInUse];

    final statuses = await toRequest.request();

    final allGranted = statuses.values.every(
        (s) => s == PermissionStatus.granted || s == PermissionStatus.limited);

    if (!allGranted) {
      _set(
          BtState.error, 'Bluetooth permissions denied. Tap to open settings.');
    }
    return allGranted;
  }

  Future<bool> get isBluetoothEnabled async {
    try {
      return await _method.invokeMethod<bool>('isBluetoothEnabled') ?? false;
    } catch (_) {
      return false;
    }
  }

  // ── Load bonded (paired) devices ──────────────────────────────────────────
  Future<void> loadBondedDevices() async {
    if (!await requestPermissions()) return;
    try {
      final raw = await _method.invokeListMethod<dynamic>('getBondedDevices');
      _bondedDevices
        ..clear()
        ..addAll((raw ?? []).map((e) => BtDevice.fromMap(e as Map)));
      notifyListeners();
    } on PlatformException catch (e) {
      _set(BtState.error, 'Failed to load paired devices: ${e.message}');
    }
  }

  // ── Discovery / scan ──────────────────────────────────────────────────────
  Future<void> startScan() async {
    if (_state == BtState.scanning) return;

    final granted = await requestPermissions();
    if (!granted) return;

    if (!await isBluetoothEnabled) {
      _set(BtState.error, 'Bluetooth is OFF. Please enable it.');
      return;
    }

    _discoveredDevices.clear();
    _set(BtState.scanning, 'Scanning for ELM327 adapters…');

    _discSub?.cancel();
    _discSub = _discEvents.receiveBroadcastStream().listen(
      (event) {
        final dev = BtDevice.fromMap(event as Map);
        if (!_discoveredDevices.contains(dev)) {
          _discoveredDevices.add(dev);
          notifyListeners();
        }
      },
      onDone: () {
        if (_state == BtState.scanning) {
          _set(BtState.idle,
              'Scan done — ${_discoveredDevices.length} device(s) found');
        }
      },
      onError: (e) => _set(BtState.error, 'Scan error: $e'),
    );

    try {
      final started =
          await _method.invokeMethod<bool>('startDiscovery') ?? false;
      if (!started) {
        _discSub?.cancel();
        _set(BtState.error, 'Could not start scan');
      }
    } on PlatformException catch (e) {
      _discSub?.cancel();
      _set(BtState.error, 'Scan failed: ${e.message}');
    }
  }

  Future<void> stopScan() async {
    await _method.invokeMethod('cancelDiscovery');
    _discSub?.cancel();
    if (_state == BtState.scanning) _set(BtState.idle, 'Scan stopped');
  }

  // ── Bond (pair) device ────────────────────────────────────────────────────
  Future<bool> bondDevice(BtDevice device) async {
    _set(BtState.bonding, 'Pairing with ${device.name}…');
    try {
      final ok = await _method
              .invokeMethod<bool>('bondDevice', {'address': device.address}) ??
          false;
      if (ok) {
        _set(BtState.idle, 'Paired with ${device.name}');
        await loadBondedDevices();
      } else {
        _set(BtState.error, 'Pairing failed');
      }
      return ok;
    } on PlatformException catch (e) {
      _set(BtState.error, 'Pairing error: ${e.message}');
      return false;
    }
  }

  // ── Connect ───────────────────────────────────────────────────────────────
  Future<bool> connect(BtDevice device) async {
    if (isConnecting || isConnected) return false;

    // Bond first if not already paired
    if (!device.bonded &&
        !_bondedDevices.any((d) => d.address == device.address)) {
      final bonded = await bondDevice(device);
      if (!bonded) return false;
    }

    _set(BtState.connecting, 'Connecting to ${device.name}…');

    try {
      final ok = await _method
              .invokeMethod<bool>('connect', {'address': device.address}) ??
          false;

      if (ok) {
        _connectedDevice = device;
        _set(BtState.connected, 'Connected to ${device.name}');
        _listenToData();
        return true;
      } else {
        _set(BtState.error, 'Connection refused by ${device.name}');
        return false;
      }
    } on PlatformException catch (e) {
      _set(BtState.error, 'Connection error: ${e.message}');
      return false;
    }
  }

  void _listenToData() {
    _dataSub?.cancel();
    _dataSub = _dataEvents.receiveBroadcastStream().listen(
      (event) => _dataCtrl.add(event as String),
      onError: (_) {
        _connectedDevice = null;
        _set(BtState.error, 'Bluetooth link lost');
      },
      onDone: () {
        _connectedDevice = null;
        _set(BtState.idle, 'Disconnected');
      },
    );
  }

  // ── Write raw command ─────────────────────────────────────────────────────
  Future<bool> write(String cmd) async {
    if (!isConnected) return false;
    try {
      return await _method.invokeMethod<bool>('write', {'data': cmd}) ?? false;
    } catch (_) {
      return false;
    }
  }

  // ── Disconnect ────────────────────────────────────────────────────────────
  Future<void> disconnect() async {
    _dataSub?.cancel();
    _dataSub = null;
    try {
      await _method.invokeMethod('disconnect');
    } catch (_) {}
    _connectedDevice = null;
    _set(BtState.idle, 'Disconnected');
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  void _set(BtState state, String message) {
    _state = state;
    _statusMessage = message;
    notifyListeners();
  }

  @override
  void dispose() {
    _discSub?.cancel();
    _dataSub?.cancel();
    _dataCtrl.close();
    super.dispose();
  }
}
