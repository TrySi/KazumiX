import 'dart:io';

import 'package:kazumi/modules/bangumi/episode_item.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

String decodeVideoSource(String iframeUrl) {
  final decodedUrl = Uri.decodeFull(iframeUrl);
  final regExp = RegExp(
    r'(http[s]?://.*?\.m3u8)|(http[s]?://.*?\.mp4)',
    caseSensitive: false,
  );

  final uri = Uri.parse(decodedUrl);
  final params = uri.queryParameters;

  var matchedUrl = iframeUrl;
  params.forEach((key, value) {
    if (regExp.hasMatch(value)) {
      matchedUrl = value;
      return;
    }
  });

  return Uri.encodeFull(matchedUrl);
}

int extractEpisodeNumber(String input) {
  // An explicit 第N话/第N集 marker wins, because a title can also carry a year
  // or a resolution and the loose fallback below would pick that up instead.
  final match =
      RegExp(r'第\s*(\d+)\s*[话集]').firstMatch(input) ??
      RegExp(r'第?(\d+)[话集]?').firstMatch(input);

  if (match != null && match.group(1) != null) {
    return int.tryParse(match.group(1)!) ?? 0;
  }

  return 0;
}

/// Normalizes an episode label for display, so different sources' formats
/// (`1`, `第1集`, `第1话`, `EP1`) render consistently as `第X话`.
///
/// Display only: it never rewrites the stored identifiers. A label carrying a
/// descriptive title keeps it and only has the 集/话 marker normalized; a label
/// that is just the episode number (optionally wrapped) becomes `第X话`.
String formatEpisodeLabel(String input) {
  final value = input.trim();
  if (value.isEmpty) return value;
  final number = extractEpisodeNumber(value);
  if (number <= 0) return value;
  final bare = RegExp('^第?\\s*0*$number\\s*[话集]?\$');
  if (bare.hasMatch(value)) return '第$number话';
  return value.replaceAll('集', '话');
}

/// Builds display titles for downloaded / offline episodes from cached Bangumi
/// metadata, so every screen reads the same: main episodes as `第X话`, extras
/// (SP/OP/ED) as `<PREFIX><index> <title>`.
class OfflineEpisodeTitles {
  const OfflineEpisodeTitles._(this._byNumber, this._byName);

  final Map<int, String> _byNumber;
  final Map<String, String> _byName;

  static const OfflineEpisodeTitles empty = OfflineEpisodeTitles._({}, {});

  factory OfflineEpisodeTitles.fromCache(Iterable<EpisodeInfo>? cached) {
    final byNumber = <int, String>{};
    final byName = <String, String>{};
    final counters = <int, int>{};
    for (final episode in cached ?? const <EpisodeInfo>[]) {
      final nameCn = episode.nameCn.trim();
      final name = episode.name.trim();
      final label = nameCn.isNotEmpty ? nameCn : name;
      if (episode.type == 0) {
        final n = episode.episode;
        if (n == n.roundToDouble() && n > 0) {
          byNumber[n.toInt()] = '第${n.toInt()}话';
        }
        continue;
      }
      final prefix = switch (episode.type) {
        1 => 'SP',
        2 => 'OP',
        3 => 'ED',
        _ => null,
      };
      if (prefix == null) continue;
      final index = (counters[episode.type] ?? 0) + 1;
      counters[episode.type] = index;
      final title = label.isNotEmpty ? '$prefix$index $label' : '$prefix$index';
      if (nameCn.isNotEmpty) byName[nameCn] = title;
      if (name.isNotEmpty) byName[name] = title;
    }
    return OfflineEpisodeTitles._(byNumber, byName);
  }

  /// Display title for an episode: extras matched by name win, then the main
  /// episode number, falling back to the stored name.
  String titleFor({required int episodeNumber, String name = ''}) {
    final trimmed = name.trim();
    if (trimmed.isNotEmpty) {
      final byNameHit = _byName[trimmed];
      if (byNameHit != null) return byNameHit;
    }
    final byNumberHit = _byNumber[episodeNumber];
    if (byNumberHit != null) return byNumberHit;
    if (trimmed.isNotEmpty) return formatEpisodeLabel(trimmed);
    return episodeNumber > 0 ? '第$episodeNumber话' : trimmed;
  }
}

Future<String> getPlayerTempPath() async {
  final directory = await getTemporaryDirectory();
  return directory.path;
}

String buildShadersAbsolutePath(String baseDirectory, List<String> shaders) {
  final absolutePaths = shaders.map((shader) {
    return path.join(baseDirectory, shader);
  }).toList();
  if (Platform.isWindows) {
    return absolutePaths.join(';');
  }
  return absolutePaths.join(':');
}
