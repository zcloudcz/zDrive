import 'package:flutter/foundation.dart';

/// Windows and POSIX both forbid `/`; Windows additionally forbids `\` and
/// `:` (drive letters), and treats a bare `.`/`..` as a directory reference
/// rather than a real entry. That second point is broader than just those
/// two literals: Win32 trims trailing dots and spaces off a path component
/// before resolving it, so `".. "`, `"..."`, `". "` and `"   "` all resolve
/// the *same way* `.`/`..` do even though none of them equal those literals
/// as strings — verified directly against this app's own path handling
/// (`Directory(p.join(root, '.. ')).delete(recursive: true)` deletes `root`
/// itself, and `p.canonicalize`/`p.isWithin` do not catch it, because they
/// only special-case the exact strings `.`/`..`; see PR #12 review round 2,
/// R1). Rejecting anything that is *only* dots and spaces closes that
/// without needing the two literal checks separately. A name has to be
/// exactly one plain path segment for `p.join` to be safe with it.
///
/// Shared between [PullSyncService] (what a server-supplied name is safe to
/// write locally) and `LocalChangeScanner` (what a local name is safe to
/// walk and report upstream) — the scanner must skip exactly what pull
/// refuses to create, or a file pull would quarantine could round-trip back
/// through push and land right back in the same quarantine.
bool isSyncableName(String name, {required bool isWindows}) =>
    name.isNotEmpty &&
    !RegExp(r'^[. ]+$').hasMatch(name) &&
    !name.contains('/') &&
    !name.contains('\\') &&
    !name.contains(':') &&
    // Win32-specific unwritable names (a trailing dot/space, a reserved
    // device stem, an illegal character) are rejected only on Windows —
    // per the PR #12 review round 3 human decision, the server does not
    // enforce these and a macOS client syncs such names normally. [isWindows]
    // is the caller's injected platform decision (defaulting to
    // [Platform.isWindows]), not a direct read of the host here, so tests can
    // exercise both branches without depending on the OS they happen to run
    // on. See [violatesWin32NameRules].
    !(isWindows && violatesWin32NameRules(name));

/// Characters Win32 forbids in a path segment beyond the ones already
/// checked above (`/`, `\`, `:`): `< > " | ? *` and the C0 control range.
/// macOS and Linux allow all of these in a filename.
final RegExp _win32IllegalChars = RegExp(r'[<>"|?*\x00-\x1F]');

/// `CON`, `PRN`, `AUX`, `NUL`, `COM0`-`COM9`, `LPT0`-`LPT9`, case-insensitive,
/// with or without an extension — `nul.txt` is just as reserved as bare
/// `nul` to this check. Whether a given one of these actually fails to
/// write is Windows version- and build-dependent (on the machine the PR #12
/// review ran its probes on, only bare `nul` failed — `aux`, `com1` and
/// `nul.txt` all wrote fine), and that dependence is exactly why they are
/// rejected up front instead of discovered at write time.
const _win32ReservedStems = {
  'con', 'prn', 'aux', 'nul', //
  'com0', 'com1', 'com2', 'com3', 'com4', 'com5', 'com6', 'com7', 'com8', 'com9', //
  'lpt0', 'lpt1', 'lpt2', 'lpt3', 'lpt4', 'lpt5', 'lpt6', 'lpt7', 'lpt8', 'lpt9',
};

/// True if Win32 cannot write [name] as given: a trailing dot or space
/// (Win32 silently trims these off before resolving a path component,
/// which is what let a remote `foo.` alias the local `foo` a sibling
/// already occupies — PR #12 review round 3, B1), one of
/// [_win32IllegalChars], or a reserved device stem. Deliberately
/// platform-agnostic: the only production call site ([isSyncableName]) gates
/// it behind the caller's injected `isWindows` decision, but the rule table
/// itself is exercised directly in tests without needing to fake the host OS.
@visibleForTesting
bool violatesWin32NameRules(String name) =>
    name.endsWith('.') ||
    name.endsWith(' ') ||
    _win32IllegalChars.hasMatch(name) ||
    _win32ReservedStems.contains(name.split('.').first.toLowerCase());

/// OS-regenerated metadata files that hold no user data — Finder writes
/// `.DS_Store` whenever a folder is opened, and Explorer writes `Thumbs.db`
/// (thumbnail cache). Left in place, either would make a folder that pull
/// otherwise emptied out look "not empty" forever, wedging every remote
/// delete of a folder that was ever opened in Finder / Explorer (PR #12
/// review round 4, C1). `desktop.ini` (Explorer's folder-view settings) is
/// deliberately NOT in this list: unlike the other two, the OS does not
/// regenerate it on its own — it is written when a user customizes a
/// folder's view, which is user intent, not OS noise, and Explorer marks
/// such folders ReadOnly, so the containing folder would fail to delete
/// anyway once the customization is gone (PR #12 review round 5, D1).
///
/// Shared between [PullSyncService] (which sweeps them when they are the
/// only thing left in a folder pull is trying to remove) and
/// `LocalChangeScanner` (which must not treat them as local files to
/// upload).
const osMetadataFileNames = ['.DS_Store', 'Thumbs.db'];
