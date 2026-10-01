/// Plays back an adapter transcript in the format the tester-mode session
/// recorder writes (`lib/services/session_recorder.dart`), as a
/// [BluetoothClassicService] the REAL [ObdService] can connect to.
///
/// See `test/fixtures/replay/README.md` for the format and for how to turn a
/// real recording into a fixture.
library;

import 'dart:async';
import 'dart:io';

import 'package:danlite_elm/services/bluetooth_classic_service.dart';

/// One command from the transcript and what came back for it.
class ReplayEntry {
  ReplayEntry(this.command, this.reply, this.delay);
  final String command;

  /// The raw reply up to (not including) the `>` prompt, or null when the
  /// transcript shows no reply at all (the adapter stayed silent).
  final String? reply;

  /// How long after the command the reply arrived, from the timestamps.
  final Duration delay;
}

/// A parsed transcript: the exchanges, the `# expect …` lines, and the
/// `# vehicle:` / `# timing:` directives.
class Transcript {
  Transcript(this.name, this.entries, this.expect, this.directives);
  final String name;
  final List<ReplayEntry> entries;
  final Map<String, String> expect;
  final Map<String, String> directives;

  static final _line = RegExp(r'^(\d\d):(\d\d):(\d\d)\.(\d{3}) (TX>|RX<)(.*)$');
  static final _expect = RegExp(r'^#\s*expect\s+([\w-]+)\s*:\s*(.*)$');
  static final _directive = RegExp(r'^#\s*(vehicle|timing|protocol-note)\s*:\s*(.*)$');

  static Duration _at(RegExpMatch m) => Duration(
        hours: int.parse(m[1]!),
        minutes: int.parse(m[2]!),
        seconds: int.parse(m[3]!),
        milliseconds: int.parse(m[4]!),
      );

  /// The recorder writes carriage returns and line feeds as `\r` and `\n`.
  static String _unescape(String s) =>
      s.replaceAll(r'\r', '\r').replaceAll(r'\n', '\n');

  factory Transcript.parse(String name, String text) {
    final entries = <ReplayEntry>[];
    final expect = <String, String>{};
    final directives = <String, String>{};
    String? cmd;
    Duration? cmdAt;
    final replies = <String>[];
    Duration? firstReplyAt;

    void flush() {
      if (cmd == null) return;
      entries.add(ReplayEntry(
        cmd!,
        replies.isEmpty ? null : replies.join('\r'),
        firstReplyAt == null ? Duration.zero : firstReplyAt! - cmdAt!,
      ));
      cmd = null;
      replies.clear();
      firstReplyAt = null;
    }

    for (final raw in text.split(RegExp(r'\r?\n'))) {
      final line = raw.trimRight();
      if (line.isEmpty) continue;
      final e = _expect.firstMatch(line);
      if (e != null) {
        expect[e[1]!] = e[2]!.trim();
        continue;
      }
      final d = _directive.firstMatch(line);
      if (d != null) {
        directives[d[1]!] = d[2]!.trim();
        continue;
      }
      if (line.startsWith('#')) continue; // recorder notes
      final m = _line.firstMatch(line);
      if (m == null) {
        throw FormatException('$name: unreadable transcript line', line);
      }
      if (m[5] == 'TX>') {
        flush();
        cmd = m[6]!.trim().toUpperCase();
        cmdAt = _at(m);
      } else {
        if (cmd == null) continue; // stray frame before any command
        firstReplyAt ??= _at(m);
        replies.add(_unescape(m[6]!));
      }
    }
    flush();
    return Transcript(name, entries, expect, directives);
  }

  static Transcript load(File f) =>
      Transcript.parse(f.uri.pathSegments.last, f.readAsStringSync());
}

/// Answers each command from the transcript.
///
/// Replies are queued per command AND per addressing context (the last
/// `ATSH` header, reset by `ATZ`, `ATSP0` and `ATAR`), in transcript order:
/// the n-th `19 02 FF` sent to `7B0` gets the n-th reply recorded for it.
/// When a queue runs out its last reply repeats — the vehicle's state is
/// taken to be stable. A command never recorded answers `OK` (AT commands),
/// a bare prompt (an empty command), or `NO DATA`, and is listed in
/// [unmatched] so a test can insist the transcript covered what mattered.
///
/// Delays come from the timestamps, multiplied by [timeScale].
class ReplayTransport extends BluetoothClassicService {
  ReplayTransport(this.transcript, {this.timeScale = 1.0}) {
    String? header;
    for (final e in transcript.entries) {
      header = _nextHeader(header, e.command);
      _queues.putIfAbsent(_key(header, e.command), () => <ReplayEntry>[]).add(e);
    }
  }

  final Transcript transcript;
  final double timeScale;
  final Map<String, List<ReplayEntry>> _queues = <String, List<ReplayEntry>>{};
  final Map<String, int> _cursor = <String, int>{};
  final List<String> wire = <String>[];
  final List<String> unmatched = <String>[];
  final _ctrl = StreamController<String>.broadcast();
  bool _connected = false;
  String? _header;

  static String? _nextHeader(String? current, String cmd) {
    if (cmd.startsWith('ATSH')) return cmd.substring(4);
    if (cmd == 'ATZ' || cmd == 'ATSP0' || cmd == 'ATAR') return null;
    return current;
  }

  static String _key(String? header, String cmd) => '${header ?? '-'}|$cmd';

  @override
  Stream<String> get dataStream => _ctrl.stream;

  @override
  bool get isConnected => _connected;

  @override
  Future<bool> connect(BtDevice device) async {
    _connected = true;
    return true;
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
  }

  @override
  Future<bool> write(String cmd) async {
    if (!_connected) return false;
    final c = cmd.trim().toUpperCase();
    wire.add(c);
    _header = _nextHeader(_header, c);

    final key = _key(_header, c);
    final q = _queues[key];
    if (q == null || q.isEmpty) {
      if (!c.startsWith('AT') && c.isNotEmpty) unmatched.add(key);
      _emit(c.isEmpty ? '' : (c.startsWith('AT') ? 'OK' : 'NO DATA'), Duration.zero);
      return true;
    }
    final i = _cursor[key] ?? 0;
    final entry = q[i < q.length ? i : q.length - 1];
    _cursor[key] = i + 1;
    if (entry.reply == null) return true; // the transcript shows silence
    _emit(entry.reply!, entry.delay * timeScale);
    return true;
  }

  void _emit(String reply, Duration delay) {
    final payload = '$reply>';
    void add() {
      if (!_ctrl.isClosed) _ctrl.add(payload);
    }

    if (delay > Duration.zero) {
      Future<void>.delayed(delay, add);
    } else {
      scheduleMicrotask(add);
    }
  }

  Future<void> close() async {
    if (!_ctrl.isClosed) await _ctrl.close();
  }
}
