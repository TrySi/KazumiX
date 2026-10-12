// Bangumi mirror API credentials for the search signature flow.
// Release/PR CI injects them via --dart-define=KAZUMI_APPID / KAZUMI_KEY.
const Map<String, String> bangumiMirrorCredentials = {
  'id': String.fromEnvironment('KAZUMI_APPID'),
  'value': String.fromEnvironment('KAZUMI_KEY'),
};

/// Whether the credentials above were injected at build time.
///
/// The mirror signs searches and comments with them, so without them those
/// endpoints cannot be used and mirror mode should not be the default.
bool get hasBangumiMirrorCredentials =>
    bangumiMirrorCredentials['id']!.isNotEmpty &&
    bangumiMirrorCredentials['value']!.isNotEmpty;
