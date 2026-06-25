/// Pure semver logic for cutting a release from conventional commits — no I/O,
/// so it is fully unit-testable. The CLI command gathers the inputs (latest tag,
/// pubspec version, the commit log) via git/file reads and calls [computeRelease];
/// the action then tags + creates the GitHub Release.
library;

/// A semantic-version bump level.
enum Bump { major, minor, patch }

/// Infer the bump from a block of conventional-commit text (subjects + bodies):
///   `<type>!:` or `BREAKING CHANGE` → major, `feat:` → minor, `fix:` → patch.
/// Anything else → patch (a deliberate cut still ships something). Highest wins.
Bump inferBump(String commitLog) {
  if (RegExp(r'^[a-z]+(\([^)]*\))?!:', multiLine: true).hasMatch(commitLog) ||
      RegExp(r'BREAKING[ -]CHANGE', caseSensitive: false).hasMatch(commitLog)) {
    return Bump.major;
  }
  if (RegExp(r'^feat(\([^)]*\))?:', multiLine: true).hasMatch(commitLog)) {
    return Bump.minor;
  }
  // `fix:` → patch; default is also patch.
  return Bump.patch;
}

/// The marketing `x.y.z` of a version string, dropping any `+build`/`-pre`.
String stripBuild(String version) {
  final m = RegExp(r'(\d+)\.(\d+)\.(\d+)').firstMatch(version);
  return m == null ? '0.0.0' : '${m[1]}.${m[2]}.${m[3]}';
}

/// The marketing `x.y.z` carried by a tag like `mobile-v1.2.3` (prefix stripped,
/// `+build` dropped). Falls back to `0.0.0` if the tag has no semver.
String baseVersionFromTag(String tag, String prefix) =>
    stripBuild(tag.startsWith(prefix) ? tag.substring(prefix.length) : tag);

/// Apply [bump] to a `x.y.z` base and return the next `x.y.z`.
String nextVersion(String base, Bump bump) {
  final p = stripBuild(base).split('.').map(int.parse).toList();
  var (major, minor, patch) = (p[0], p[1], p[2]);
  switch (bump) {
    case Bump.major:
      major++;
      minor = 0;
      patch = 0;
    case Bump.minor:
      minor++;
      patch = 0;
    case Bump.patch:
      patch++;
  }
  return '$major.$minor.$patch';
}

/// The resolved release: the next version, its tag, and the bump that produced it.
class ReleaseComputation {
  const ReleaseComputation({
    required this.version,
    required this.tag,
    required this.bump,
  });

  final String version;
  final String tag;
  final Bump bump;
}

/// Compute the next release from the inputs the CLI gathered.
///
/// Baseline = the latest `<prefix>*` tag (else the pubspec marketing version).
/// [bumpInput] is `auto` (infer from [commitLog]) or an explicit level.
ReleaseComputation computeRelease({
  required String tagPrefix,
  required String? latestTag,
  required String pubspecVersion,
  required String bumpInput,
  required String commitLog,
}) {
  final base = (latestTag != null && latestTag.isNotEmpty)
      ? baseVersionFromTag(latestTag, tagPrefix)
      : stripBuild(pubspecVersion);
  final bump = bumpInput == 'auto'
      ? inferBump(commitLog)
      : Bump.values.byName(bumpInput);
  final version = nextVersion(base, bump);
  return ReleaseComputation(
    version: version,
    tag: '$tagPrefix$version',
    bump: bump,
  );
}
