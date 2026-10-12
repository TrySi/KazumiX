// DanDanPlay API credentials for the client signature flow.
// Release/PR CI injects them via --dart-define=DANDANAPI_APPID / DANDANAPI_KEY.
const Map<String, String> dandanCredentials = {
  'id': String.fromEnvironment('DANDANAPI_APPID'),
  'value': String.fromEnvironment('DANDANAPI_KEY'),
};

/// Whether the credentials above were injected at build time.
///
/// Every DanDanPlay request is signed with them, so a build without them would
/// fail each call with HTTP 403. Callers check this and keep the whole danmaku
/// feature off instead of issuing requests that cannot succeed.
bool get hasDandanCredentials =>
    dandanCredentials['id']!.isNotEmpty &&
    dandanCredentials['value']!.isNotEmpty;
