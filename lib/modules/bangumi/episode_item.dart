class EpisodeInfo {
  int id;
  num episode;
  int type;
  String name;
  String nameCn;
  DateTime? airDate;

  EpisodeInfo({
    required this.id,
    required this.episode,
    required this.type,
    required this.name,
    required this.nameCn,
    this.airDate,
  });

  factory EpisodeInfo.fromJson(Map<String, dynamic> json) {
    final airDateText = json['airdate']?.toString().trim() ?? '';
    return EpisodeInfo(
      id: json['id'] ?? 0,
      episode: json['sort'] ?? 0,
      type: json['type'] ?? 0,
      name: json['name'] ?? '',
      nameCn: json['name_cn'] ?? '',
      airDate: airDateText.isEmpty ? null : DateTime.tryParse(airDateText),
    );
  }

  factory EpisodeInfo.fromTemplate() {
    return EpisodeInfo(id: 0, episode: 0, type: 0, name: '', nameCn: '');
  }

  void reset() {
    id = 0;
    episode = 0;
    type = 0;
    name = '';
    nameCn = '';
  }

  String readType() {
    switch (type) {
      case 0:
        return 'ep';
      case 1:
        return 'sp';
      case 2:
        return 'op';
      case 3:
        return 'ed';
      default:
        return '';
    }
  }
}
