import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/services/network/bangumi_acceleration.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/utils/bangumi_mirror_credentials.dart';
import 'package:logger/logger.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _TestPaths extends PathProviderPlatform {
  _TestPaths(this.root);

  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;

  @override
  Future<String?> getTemporaryPath() async => root;
}

void main() {
  // The missing-credentials warning is logged, and the sink needs bindings.
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  late PathProviderPlatform originalPathProvider;

  setUpAll(() async {
    Logger.level = Level.off;
    directory = await Directory.systemTemp.createTemp('kazumi_accel_test_');
    originalPathProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _TestPaths(directory.path);
    Hive.init(directory.path);
    await GStorage.init();
  });

  tearDownAll(() async {
    await Hive.close();
    PathProviderPlatform.instance = originalPathProvider;
    await directory.delete(recursive: true);
  });

  setUp(() async {
    await GStorage.putSetting(SettingsKeys.bangumiAcceleration, '');
    await GStorage.putSetting(SettingsKeys.enableBangumiProxy, false);
  });

  test('an explicit choice always wins', () async {
    for (final mode in BangumiAcceleration.values) {
      await GStorage.putSetting(SettingsKeys.bangumiAcceleration, mode.name);
      expect(BangumiAcceleration.current, mode);
    }
  });

  test('the legacy switch only decides while no choice was made', () async {
    await GStorage.putSetting(SettingsKeys.enableBangumiProxy, false);
    expect(BangumiAcceleration.current, BangumiAcceleration.direct);

    await GStorage.putSetting(SettingsKeys.enableBangumiProxy, true);
    final expected = hasBangumiMirrorCredentials
        ? BangumiAcceleration.mirror
        : BangumiAcceleration.direct;
    expect(BangumiAcceleration.current, expected);
  });
}
