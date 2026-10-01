/// Danlite ELM — tester-mode session recorder.
///
/// Records the raw adapter conversation of one connection to a local text
/// file: when it started, the adapter's identity reply, the protocol the
/// adapter detected, and every command and reply with a timestamp. Its purpose
/// is to learn which protocol real Indian bikes speak and to turn real
/// exchanges into test fixtures (there are none from real bikes today).
///
/// Rules, each enforced here and tested in `test/session_recorder_test.dart`:
///   * OFF by default, and not remembered across app restarts. It is switched
///     on only from the hidden control in Settings (seven taps on the version
///     line), and a notice is shown while it is on.
///   * Local only. The file is written to the app's no-backup directory
///     (excluded from Android Auto Backup), and this class contains no network
///     code. The ONLY way a recording leaves the phone is the rider pressing
///     Share, which hands the text to the Android share sheet.
///   * Never reaches Sentry: nothing here logs, prints or reports.
///   * Any vehicle identification number is masked before it is written.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Where recordings live and how one is shared. Swapped out in tests.
abstract class RecorderStorage {
  /// A private, not-backed-up directory for recordings.
  Future<Directory> directory();

  /// Hand [text] to the platform share sheet. Called only from a rider tap.
  Future<void> shareText(String text, {required String subject});
}

/// Android implementation, over a small channel in `MainActivity.kt`.
class PlatformRecorderStorage implements RecorderStorage {
  static const _channel = MethodChannel('com.danlite.elm/session_recorder');

  @override
  Future<Directory> directory() async {
    try {
      final path = await _channel.invokeMethod<String>('directory');
      if (path != null && path.isNotEmpty) {
        return Directory(path).create(recursive: true);
      }
    } catch (_) {
      // Fall through to the app's own temporary directory.
    }
    return Directory('${Directory.systemTemp.path}/session_recordings')
        .create(recursive: true);
  }

  @override
  Future<void> shareText(String text, {required String subject}) =>
      _channel.invokeMethod<void>(
          'shareText', <String, String>{'text': text, 'subject': subject});
}

/// Masks anything shaped like a 17-character vehicle identification number.
///
/// A VIN uses digits and capital letters except I, O and Q. To avoid masking
/// a 17-character run of adapter hex (which uses only 0–9 and A–F), a match is
/// masked when it also contains at least one letter outside A–F — true of
/// essentially every real VIN, whose manufacturer prefix and model letters
/// fall outside hex. Replies to a Mode 09 request (vehicle information, where
/// the VIN is sent as hex-encoded text) are masked whole by the recorder.
String maskVin(String text) {
  return text.replaceAllMapped(
    RegExp(r'(?<![A-Za-z0-9])[A-HJ-NPR-Z0-9]{17}(?![A-Za-z0-9])'),
    (m) {
      final s = m.group(0)!;
      final hasNonHexLetter = RegExp(r'[G-HJ-NPR-Z]').hasMatch(s);
      final hasDigit = RegExp(r'[0-9]').hasMatch(s);
      return (hasNonHexLetter && hasDigit) ? '[VIN masked]' : s;
    },
  );
}

class SessionRecorder extends ChangeNotifier {
  SessionRecorder({RecorderStorage? storage, DateTime Function()? clock})
      : _storage = storage ?? PlatformRecorderStorage(),
        _clock = clock ?? DateTime.now;

  final RecorderStorage _storage;
  final DateTime Function() _clock;

  /// Upper bound on what one Share hands to the share sheet. Android limits
  /// the size of data passed between apps; a longer recording is cut at the
  /// end with a note, and stays complete on the phone.
  static const int maxShareChars = 400000;

  bool _enabled = false;

  /// Whether tester mode is on. Defaults to false on every app start.
  bool get enabled => _enabled;

  Directory? _dir;
  RandomAccessFile? _out;
  File? _currentFile;
  File? _lastFile;
  String _lastCommand = '';

  /// The recording currently being written, or the most recent one.
  File? get lastRecording => _currentFile ?? _lastFile;

  /// Turn tester mode on or off. Turning it off closes any open recording.
  Future<void> setEnabled(bool on) async {
    if (on == _enabled) return;
    if (on) {
      _dir = await _storage.directory();
      _enabled = true;
    } else {
      await endSession(reason: 'recorder switched off');
      _enabled = false;
    }
    notifyListeners();
  }

  /// Start a new recording for a new adapter connection.
  void beginSession({required String transport}) {
    if (!_enabled || _dir == null) return;
    _closeCurrent();
    final now = _clock();
    final stamp = now
        .toIso8601String()
        .replaceAll(RegExp(r'[:.]'), '-')
        .substring(0, 19);
    final file = File('${_dir!.path}/danlite_session_$stamp.txt');
    try {
      _out = file.openSync(mode: FileMode.write);
      _currentFile = file;
      _lastCommand = '';
      _write('# Danlite ELM session recording');
      _write('# started: ${now.toIso8601String()}');
      _write('# transport: $transport');
      _write('# format: <time> TX> command | RX< reply (\\r = carriage '
          'return); # lines are notes');
      notifyListeners();
    } catch (_) {
      _out = null;
      _currentFile = null;
    }
  }

  /// One command sent (`TX>`) or reply received (`RX<`).
  void recordExchange(String direction, String data) {
    if (_out == null) return;
    final isTx = direction.startsWith('TX');
    var text = data.replaceAll('\r', r'\r').replaceAll('\n', r'\n');
    if (isTx) {
      _lastCommand = data.trim().toUpperCase();
    } else if (_lastCommand.startsWith('09')) {
      // Mode 09 carries the VIN (and calibration IDs) as hex-encoded text,
      // which [maskVin] cannot see. Mask the whole reply.
      text = '[mode 09 reply masked]';
    }
    _write('${_timestamp()} $direction${maskVin(text)}');
  }

  /// A note: adapter identity, detected protocol, read outcome.
  void recordNote(String note) {
    if (_out == null) return;
    _write('# ${_timestamp()} ${maskVin(note)}');
  }

  /// Close the current recording, if one is open.
  Future<void> endSession({String? reason}) async {
    if (_out == null) return;
    _write('# ended: ${_clock().toIso8601String()}'
        '${reason == null ? '' : ' ($reason)'}');
    _closeCurrent();
    notifyListeners();
  }

  /// Share the most recent recording through the platform share sheet.
  /// Returns false when there is nothing to share. Only ever called from a
  /// rider's tap.
  Future<bool> shareLastRecording() async {
    final file = lastRecording;
    if (file == null || !file.existsSync()) return false;
    var text = await file.readAsString();
    if (text.length > maxShareChars) {
      text = '${text.substring(0, maxShareChars)}\n'
          '# [cut here for sharing; the full recording is on the phone]';
    }
    await _storage.shareText(text,
        subject: 'Danlite session recording ${file.uri.pathSegments.last}');
    return true;
  }

  void _closeCurrent() {
    try {
      _out?.closeSync();
    } catch (_) {}
    _out = null;
    if (_currentFile != null) _lastFile = _currentFile;
    _currentFile = null;
  }

  void _write(String line) {
    try {
      _out?.writeStringSync('$line\n');
    } catch (_) {
      // A recorder that cannot write must never disturb the connection.
    }
  }

  String _timestamp() => _clock().toIso8601String().substring(11, 23);

  @override
  void dispose() {
    _closeCurrent();
    super.dispose();
  }
}
