import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/utils/media.dart';

void main() {
  group('formatEpisodeLabel', () {
    test('normalizes bare numbers and 集/话 markers to 第X话', () {
      expect(formatEpisodeLabel('1'), '第1话');
      expect(formatEpisodeLabel('01'), '第1话');
      expect(formatEpisodeLabel('12'), '第12话');
      expect(formatEpisodeLabel('第1集'), '第1话');
      expect(formatEpisodeLabel('第1话'), '第1话');
      expect(formatEpisodeLabel('第 3 集'), '第3话');
    });

    test('keeps descriptive titles but normalizes the 集 marker', () {
      expect(formatEpisodeLabel('第1集 开端'), '第1话 开端');
      expect(formatEpisodeLabel('第1话 开端'), '第1话 开端');
      expect(formatEpisodeLabel('特别篇'), '特别篇');
    });

    test('leaves labels without a number untouched', () {
      expect(formatEpisodeLabel('OVA'), 'OVA');
      expect(formatEpisodeLabel(''), '');
    });
  });
}
