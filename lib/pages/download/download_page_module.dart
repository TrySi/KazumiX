import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/pages/download/download_page.dart';
import 'package:kazumi/pages/download/download_controller.dart';

/// Builds a fresh module instance. The download page is reachable from two
/// mounts (`/tab/download/` and `/settings/download/`), and flutter_modular
/// dedups modules by identity, so each mount needs its own instance.
Module createDownloadModule() => createModule(
  path: '/download',
  register: (c) {
    c.route(
      '/',
      child: (context, state) => DownloadPage(
        controller: inject<DownloadController>(),
      ),
    );
  },
);
