import 'package:flutter_test/flutter_test.dart';

import 'package:kazumi/modules/search/search_name_match.dart';

void main() {
  group('searchNameMatchScore', () {
    // The case this exists for: one query returns a film and its sequel, and the
    // sequel's title contains the film's title verbatim.
    const sequel = '机动战士高达：闪光的哈萨维--喀耳刻的魔女';
    const film = '机动战士高达：闪光的哈萨维';

    test('the sequel beats the film it shares a prefix with', () {
      final sequelScore = searchNameMatchScore(sequel, sequel);
      final filmScore = searchNameMatchScore(sequel, film);
      expect(sequelScore, 1);
      expect(filmScore, lessThan(sequelScore));
      // The film's 11 pairs are all present in the sequel's 17.
      expect(filmScore, closeTo(11 / 17, 0.01));
    });

    test('a title that only shares a prefix ranks below the full title', () {
      final partial = searchNameMatchScore(sequel, '机动战士高达 闪光的哈萨维 第1部');
      expect(partial, lessThan(searchNameMatchScore(sequel, sequel)));
      expect(partial, greaterThan(0));
    });

    test('separators, width and case do not change the score', () {
      const query = 'ＬＯＶＥ Ｌｉｖｅ！Ｓｕｎｓｈｉｎｅ!!';
      expect(searchNameMatchScore(query, 'love live sunshine'), 1);
      expect(searchNameMatchScore(query, 'Love Live! Sunshine!!'), 1);
    });

    test('a title with an inserted marker still scores high', () {
      final score = searchNameMatchScore('葬送的芙莉莲', '葬送的芙莉莲 第1季');
      expect(score, 1);
    });

    test('unrelated titles score zero', () {
      // They share the character 的, which must not count on its own.
      expect(searchNameMatchScore('葬送的芙莉莲', '进击的巨人'), 0);
      expect(searchNameMatchScore('葬送的芙莉莲', ''), 0);
      expect(searchNameMatchScore('', '葬送的芙莉莲'), 0);
    });

    test('a title sharing one common character with no pair scores zero', () {
      expect(searchNameMatchScore('进击的巨人', '巨神兵传奇'), 0);
    });

    test('a short query cannot be fooled by a long title', () {
      // The contained title scores 1; the other direction shares only the pair
      // 高达, and the score is bounded by the query rather than the candidate.
      expect(searchNameMatchScore('高达', '机动战士高达闪光的哈萨维'), 1);
      expect(searchNameMatchScore('机动战士高达闪光的哈萨维', '高达'), closeTo(1 / 11, 0.01));
    });
  });
}
