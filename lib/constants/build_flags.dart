/// Danlite ELM — compile-time build switches.
///
/// Both are `const`, so the compiler folds them: code behind a `false` switch
/// is dead and is not shipped as reachable logic.
library;

/// True for a build destined for a public app store, made with
/// `flutter build ... --dart-define=STORE_BUILD=true`.
const bool kStoreBuild = bool.fromEnvironment('STORE_BUILD');

/// Gates every runtime use of the engine fault text whose stated source is
/// Torque Pro: the corrupted Hindi dictionary (`DtcDictionaryHi`) and the
/// English/Hindi translations asset (`assets/dtc_translations.json`).
///
/// No licence or permission for that text is recorded anywhere
/// (FAULT_ASSET_INVENTORY.md §D5), so it is kept for closed testing only.
/// It defaults to ON, and is forced OFF in a store build — there is no way to
/// turn it on when `STORE_BUILD=true`. `test/store_build_guard_test.dart`
/// fails if that ever stops being true.
///
/// When OFF, an engine code with no other verified text is shown by its
/// structure (system, subsystem, "no verified description yet"), and a
/// manufacturer-defined code by the manufacturer-specific notice.
const bool kUseLegacyEngineText = !kStoreBuild;

/// The rule behind [kUseLegacyEngineText], as a function so the store-build
/// case can be tested without a store build. The guard test asserts the two
/// agree.
bool legacyEngineTextAllowed({required bool storeBuild}) => !storeBuild;
