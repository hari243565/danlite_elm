# Replay fixtures

Each `.txt` file here is an adapter conversation in **exactly the format the tester-mode session recorder
writes** (`lib/services/session_recorder.dart`), plus a few `# expect` lines saying what the app must make of
it. `test/replay_fixtures_test.dart` plays every file in this folder through the real `ObdService` with
`test/support/replay_transport.dart` and checks each expectation. A file with no `# expect` line fails the
suite, so nothing in here is silently untested.

Every fixture present today is **hand-written** from the ELM327, SAE J1979 and ISO 14229 byte layouts and
says so in its header. None is recorded from a real bike yet.

## Line format

```
09:30:02.000 TX>03                         a command the app sent
09:30:02.040 RX<\r7E8 06 43 02 01 33 03 01\r\r   what came back, up to the > prompt
# 09:30:02.050 engine read: EngineAnswered     a recorder note (ignored)
```

- `\r` and `\n` inside a reply are written as the two characters backslash-r / backslash-n, as the recorder does.
- A `TX>` with no `RX<` before the next `TX>` means the adapter stayed **silent** (the app's window times out).
- The gap between a `TX>` and its `RX<` timestamps is replayed as a delay (that is how an adapter that waits
  internally on "response pending" is represented).
- Replies are matched per command **and per `ATSH` address**, in order: the second `1902FF` sent to `7B0` gets
  the second reply recorded for `7B0`. When the recorded replies run out, the last one repeats. A command that
  was never recorded answers `OK` (AT commands) or `NO DATA`.

## Directives

| Line | Meaning |
|---|---|
| `# vehicle: Royal Enfield / Classic 350` | make / model for the ABS scan |
| `# timing: 0.2` | run the transcript's delays AND the app's fault-read timings at this scale |

## Expectations

| Line | Checks |
|---|---|
| `# expect engine: answered P0133 P0301` | positive Mode 03 answer with exactly these codes (`answered` alone = no codes) |
| `# expect engine: noAnswer unableToConnect` | no answer, with that `EngineNoAnswerReason` |
| `# expect engine: refused 22` | negative response, NRC 0x22 |
| `# expect engine: klineGated` | K-line bus, nothing parsed |
| `# expect vehicleAnswered: false` | the bike never gave a positive reply |
| `# expect display: P0133 P0301 P0113` | the engine cards, after merging Mode 07 / 0A |
| `# expect pending: none` / `unsupported` / codes | Mode 07 result |
| `# expect permanent: …` | Mode 0A result, same forms |
| `# expect lamp: on` / `off` | PID 01 01 lamp bit |
| `# expect engineState: running` / `off` / `unknown` | from PID 01 0C |
| `# expect voltage: low 11.2` / `normal` / `unknown` | battery voltage level (and value) |
| `# expect mayBeFalse: U0100` | these codes carry the low-voltage "may be false" label |
| `# expect vin: valid` / `invalid` / `unsupported` | Mode 09 PID 02 |
| `# expect passesPending: true` | the adapter was seen passing "response pending" through |
| `# expect abs: C1058-11` | ABS scan result as code-failure type (`clean` / `none` also accepted) |
| `# expect absStatus: 2F` | the first ABS code's status byte |
| `# expect module: 18DAF110` | the module the first engine code came from |
| `# expect extras: none` | no optional extras were sent at all |
| `# expect snapshot: answered P0301` / `noSnapshot` / `unsupported` / `noAnswer` / `refused 22` / `gated` | the on-demand Mode 02 snapshot read (Phase A-4); a fixture with any `snapshot`/`counters`/`readiness` line also runs the context read |
| `# expect snapshotValues: 04=50.2 0C=1000` | PID (hex) = value for the numeric snapshot values that were read, exactly this set |
| `# expect snapshotUnread: 05` / `none` | values the bike said it keeps but gave no usable answer |
| `# expect counters: lampKm=120 clearedKm=unsupported warmUps=noAnswer` | the lamp / clear-codes counters (`lampKm`, `clearedKm`, `lampMin`, `clearedMin`, `warmUps`): a number, `unsupported`, `noAnswer` or `atLeast` |
| `# expect readiness: misfire=complete evaporative=notComplete heatedCatalyst=notSupported` | emission self-check states (or `unsupported` / `noAnswer` for the whole read) |
| `# expect contextWire: none` | none of the on-demand context requests were sent (a plain scan never sends them) |

## Adding a real recording

1. Turn on tester mode (seven taps on the version line in Settings), connect, read the codes, and share the
   recording.
2. Save it here as `<bike>_<what it shows>.txt`. Keep the recorder's masking (`[VIN masked]`, `[mode 09 reply
   masked]`); never unmask a VIN.
3. Add a line under the header saying where it came from (bike, year, adapter) and that it is a **real
   recording**, then the `# expect` lines for what a technician agrees the bike actually has.
4. Run `flutter test test/replay_fixtures_test.dart`.
