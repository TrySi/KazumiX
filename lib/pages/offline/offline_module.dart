import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/pages/download/download_controller.dart';
import 'package:kazumi/pages/offline/offline_page.dart';

/// The offline browser mounted at `/tab/download/`. It shows downloaded
/// content grouped by show, in a collect-style layout, and is intentionally
/// separate from the download manager (`createDownloadModule`) mounted at
/// `/settings/download/`.
Module createOfflineModule() => createModule(
  path: '/download',
  register: (c) {
    c.route(
      '/',
      transition: TransitionType.none,
      child: (context, state) => OfflinePage(
        controller: inject<DownloadController>(),
      ),
    );
  },
);
