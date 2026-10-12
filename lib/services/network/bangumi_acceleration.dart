import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/utils/bangumi_mirror_credentials.dart';

enum BangumiAcceleration {
  direct,
  ech,
  mirror;

  static bool _warnedMirrorUnavailable = false;

  /// Mode used to route Bangumi requests.
  ///
  /// A stored choice always wins. While the user has never picked one the
  /// legacy mirror switch decides, except that a build without the mirror
  /// credentials cannot sign searches and comments, so it stays on direct.
  static BangumiAcceleration get current =>
      switch (GStorage.getSetting(SettingsKeys.bangumiAcceleration)) {
        'direct' => direct,
        'ech' => ech,
        'mirror' => mirror,
        _ => _unsetDefault,
      };

  static BangumiAcceleration get _unsetDefault {
    if (!GStorage.getSetting(SettingsKeys.enableBangumiProxy)) return direct;
    if (hasBangumiMirrorCredentials) return mirror;
    if (!_warnedMirrorUnavailable) {
      _warnedMirrorUnavailable = true;
      KazumiLogger().w(
        'Network: KAZUMI_APPID/KAZUMI_KEY missing at build time, '
        'defaulting Bangumi acceleration to direct',
      );
    }
    return direct;
  }

  String get label => switch (this) {
    direct => '直连',
    ech => 'ECH',
    mirror => '镜像',
  };
}
