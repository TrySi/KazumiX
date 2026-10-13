/// How closely a source's title matches the title the user opened, in `0..1`.
///
/// Sources return a whole title family for one query: a film and its sequel
/// share a prefix (`机动战士高达：闪光的哈萨维` and
/// `机动战士高达：闪光的哈萨维--喀耳刻的魔女`), and a remake, a compilation or a
/// same-name spin-off look alike too. A substring test cannot order those, while
/// the user opened exactly one of them, so the score is the share of the query
/// the candidate carries: one holding only the shared prefix scores lower than
/// one holding all of it.
///
/// Compared by character *pair* rather than by character, because titles share a
/// lot of single characters (`的`, `之`, `剧`) that mean nothing on their own:
/// `葬送的芙莉莲` and `进击的巨人` have only 的 in common, and counting characters
/// alone would call that a match.
///
/// Only scores of candidates for the same query are compared, so this is
/// deliberately a relative measure rather than a similarity metric.
double searchNameMatchScore(String query, String candidate) {
  final normalizedQuery = _normalizeTitle(query);
  final normalizedCandidate = _normalizeTitle(candidate);
  if (normalizedQuery.isEmpty || normalizedCandidate.isEmpty) return 0;
  final queryPairs = _pairs(normalizedQuery.runes.toList(growable: false));
  if (queryPairs.isEmpty) {
    // A one-character title has no pair to compare, so it can only be matched
    // whole.
    return normalizedCandidate.contains(normalizedQuery) ? 1 : 0;
  }
  final candidatePairs = _pairs(
    normalizedCandidate.runes.toList(growable: false),
  ).toSet();
  var matched = 0;
  for (final pair in queryPairs) {
    if (candidatePairs.contains(pair)) matched++;
  }
  return matched / queryPairs.length;
}

/// Keeps only the characters that carry a title, and lowercases the rest, so
/// `机动战士高达 闪光的哈萨维` and `机动战士高达：闪光的哈萨维` compare equal.
/// Separators, brackets and full-width punctuation are dropped.
String _normalizeTitle(String input) {
  final buffer = StringBuffer();
  for (var rune in input.runes) {
    // Full-width ASCII (Ａ-ｚ, ０-９) sits a fixed offset from its half-width
    // form, and sources mix the two freely.
    if (rune >= 0xFF01 && rune <= 0xFF5E) rune -= 0xFEE0;
    if ((rune >= 0x30 && rune <= 0x39) ||
        (rune >= 0x41 && rune <= 0x5A) ||
        (rune >= 0x61 && rune <= 0x7A)) {
      buffer.writeCharCode(rune >= 0x41 && rune <= 0x5A ? rune + 0x20 : rune);
      continue;
    }
    final isIdeograph = rune >= 0x3400 && rune <= 0x9FFF;
    final isKana = rune >= 0x3040 && rune <= 0x30FF;
    final isHangul = rune >= 0xAC00 && rune <= 0xD7A3;
    if (isIdeograph || isKana || isHangul) buffer.writeCharCode(rune);
  }
  return buffer.toString();
}

/// Every adjacent character pair of [runes], as a packed int.
///
/// Both characters are packed into one value so pairs compare and index without
/// building a substring for every position.
List<int> _pairs(List<int> runes) {
  if (runes.length < 2) return const [];
  return [
    for (var i = 0; i < runes.length - 1; i++) (runes[i] << 21) | runes[i + 1],
  ];
}
