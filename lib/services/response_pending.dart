/// Danlite ELM — "request received, response pending" (negative response
/// code 0x78), handled the same way for every read.
///
/// A module that needs more time answers `7F <service> 78` and sends the real
/// answer later; the standard has the tester restart its timer on a longer
/// limit and keep waiting. Adapters differ, and their version strings cannot be
/// trusted (clones report any version), so behaviour is detected instead:
///
///  * Genuine ELM327 2.1+ and STN chips wait inside the adapter (about five
///    seconds per pending) and return only the final answer. To the app that
///    is just a slow reply — so the request window must be long enough
///    ([kPendingPerAttemptWindow]), and nothing else is needed.
///  * Most cheap clones are ELM 1.x designs: they print the `7F xx 78` line,
///    hand back the prompt, and the real answer that arrives afterwards is
///    lost. The only way to get it is to ask again. These reads are safe to
///    repeat, so the SAME request is re-sent after [kPendingRetryDelay], until
///    an answer arrives or [kPendingOverallBound] passes.
///
/// A module that is still busy at the bound ends as [PendingBusy] — "module
/// kept reporting busy" — never as an empty list and never as success.
library;

import 'fault_decoders.dart';

/// How long one request may take, long enough for an adapter that waits
/// internally on a pending response.
const Duration kPendingPerAttemptWindow = Duration(seconds: 5);

/// The most time one read may spend on a module that keeps answering pending.
const Duration kPendingOverallBound = Duration(seconds: 20);

/// The pause before re-sending a request after a passed-through pending frame.
/// A starting value, to be confirmed at the final live test.
const Duration kPendingRetryDelay = Duration(milliseconds: 300);

class PendingPolicy {
  const PendingPolicy({
    this.perAttempt = kPendingPerAttemptWindow,
    this.overall = kPendingOverallBound,
    this.retryDelay = kPendingRetryDelay,
  });

  final Duration perAttempt;
  final Duration overall;
  final Duration retryDelay;
}

sealed class PendingResult {
  const PendingResult({required this.attempts, required this.sawPending});

  /// How many times the request was sent.
  final int attempts;

  /// A pending frame was seen at least once.
  final bool sawPending;
}

/// The read ended with a reply that is not a pending frame: the module's
/// answer, a refusal, `NO DATA`, or the service's own `TIMEOUT` /
/// `DISCONNECTED` marker. Any pending lines are removed from [reply], so the
/// normal decoder sees only the real answer.
final class PendingAnswered extends PendingResult {
  const PendingAnswered(this.reply,
      {required super.attempts, required super.sawPending});
  final String reply;
}

/// The module kept answering "response pending" until the overall bound.
final class PendingBusy extends PendingResult {
  const PendingBusy({required super.attempts}) : super(sawPending: true);

  String get reason => 'module kept reporting busy';
}

/// The caller asked to stop (disconnect, or the link is needed elsewhere)
/// while the module was still answering "response pending".
final class PendingCancelled extends PendingResult {
  const PendingCancelled({required super.attempts}) : super(sawPending: true);
}

/// Send [request] (UDS / OBD service [serviceId]) and see it through any
/// number of response-pending frames.
///
/// [send] performs one request with the given window and returns the
/// sanitised reply or a `TIMEOUT` / `DISCONNECTED` / `ERROR` marker. [flush]
/// is called before giving up whenever a request may still be outstanding in
/// the adapter — after a timeout, or when abandoning a busy module — so the
/// next command never receives this one's late reply. [onAdapterPassesPending]
/// fires when a pending frame reaches the app, i.e. the adapter did not
/// absorb it. [sleep] and [elapsed] exist so tests can use a fake clock.
Future<PendingResult> sendWithPendingHandling({
  required String request,
  required int serviceId,
  required Future<String> Function(String request, Duration window) send,
  Future<void> Function({required bool afterTimeout})? flush,
  void Function()? onAdapterPassesPending,
  PendingPolicy policy = const PendingPolicy(),
  Future<void> Function(Duration)? sleep,
  Duration Function()? elapsed,
  bool Function()? isCancelled,
}) async {
  final watch = Stopwatch()..start();
  final now = elapsed ?? () => watch.elapsed;
  final start = now();
  final pause = sleep ?? (d) => Future<void>.delayed(d);
  var attempts = 0;
  var sawPending = false;

  while (true) {
    final remaining = policy.overall - (now() - start);
    if (remaining <= Duration.zero) {
      await flush?.call(afterTimeout: false);
      return PendingBusy(attempts: attempts);
    }
    final window = remaining < policy.perAttempt ? remaining : policy.perAttempt;
    final reply = await send(request, window);
    attempts++;

    final upper = reply.trim().toUpperCase();
    if (upper == 'TIMEOUT') {
      // The adapter may still be working on it. Interrupt and drain before
      // anything else is sent.
      await flush?.call(afterTimeout: true);
      return PendingAnswered(reply, attempts: attempts, sawPending: sawPending);
    }

    final stripped = stripResponsePending(reply, serviceId);
    if (!stripped.sawPending) {
      return PendingAnswered(reply, attempts: attempts, sawPending: sawPending);
    }
    sawPending = true;
    onAdapterPassesPending?.call();
    if (!stripped.onlyPending) {
      // The answer followed the pending frame inside the adapter's own
      // window: keep the answer, drop the pending line.
      return PendingAnswered(stripped.rest,
          attempts: attempts, sawPending: true);
    }

    if ((now() - start) + policy.retryDelay >= policy.overall) {
      await flush?.call(afterTimeout: false);
      return PendingBusy(attempts: attempts);
    }
    await pause(policy.retryDelay);
    if (isCancelled?.call() ?? false) {
      await flush?.call(afterTimeout: false);
      return PendingCancelled(attempts: attempts);
    }
  }
}
