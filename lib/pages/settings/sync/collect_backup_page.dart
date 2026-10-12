import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/bean/settings/settings_detail_scaffold.dart';
import 'package:kazumi/bean/settings/settings_list.dart';
import 'package:kazumi/bean/widget/state_presentation.dart';
import 'package:kazumi/pages/collect/collect_controller.dart';
import 'package:kazumi/pages/settings/sync/sync_settings_widgets.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/sync/collect_backup_service.dart';
import 'package:kazumi/utils/device.dart';

enum _BackupAction { export, import }

/// Settings page that backs up the 追番 (collect) library to a local JSON file
/// and restores it on any device.
class CollectBackupPage extends StatefulWidget {
  const CollectBackupPage({super.key, required this.controller});

  final CollectController controller;

  @override
  State<CollectBackupPage> createState() => _CollectBackupPageState();
}

class _CollectBackupPageState extends State<CollectBackupPage> {
  _BackupAction? _action;

  bool get _busy => _action != null;

  @override
  void initState() {
    super.initState();
    // The list is only filled once loaded; the collect tab may not have run.
    widget.controller.loadCollectibles();
  }

  void _toast(String message) {
    if (mounted) KazumiDialog.showToast(message: message);
  }

  /// Writes the local collect library to a user-chosen JSON file.
  Future<void> _export() async {
    if (_busy) return;
    final items = widget.controller.collectibles.toList(growable: false);
    if (items.isEmpty) {
      _toast('暂无可导出的追番');
      return;
    }
    setState(() => _action = _BackupAction.export);
    try {
      final bytes = Uint8List.fromList(
        utf8.encode(CollectBackupService.instance.encode(items)),
      );
      final path = await FilePicker.platform.saveFile(
        dialogTitle: '导出追番备份',
        fileName: CollectBackupService.instance.suggestedFileName(
          DateTime.now(),
        ),
        type: FileType.custom,
        allowedExtensions: const ['json'],
        bytes: bytes,
        lockParentWindow: true,
      );
      if (path == null) return; // Cancelled.
      // Mobile writes the payload itself from `bytes`; desktop ignores
      // `bytes`, so write it manually. The returned path may be a content
      // URI on Android, which File cannot handle.
      if (isDesktop()) {
        final file = File(path);
        if (!await file.exists() || await file.length() == 0) {
          await file.writeAsBytes(bytes, flush: true);
        }
      }
      _toast('已导出 ${items.length} 部追番');
    } catch (error) {
      KazumiLogger().w('CollectBackupPage: failed to export', error: error);
      _toast('导出失败，请重试');
    } finally {
      if (mounted) setState(() => _action = null);
    }
  }

  /// Reads a JSON backup and merges it into the local collect library.
  Future<void> _import() async {
    if (_busy) return;
    setState(() => _action = _BackupAction.import);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json'],
        withData: true,
      );
      if (result == null) return; // Cancelled.
      final picked = result.files.single;
      final bytes =
          picked.bytes ??
          (picked.path == null ? null : await File(picked.path!).readAsBytes());
      if (bytes == null) throw const FileSystemException('无法读取所选文件');

      final parsed = CollectBackupService.instance.decode(utf8.decode(bytes));
      if (!mounted) return;

      final skippedNote = parsed.skipped > 0
          ? '\n其中 ${parsed.skipped} 条无法识别，将被忽略。'
          : '';
      final confirmed = await KazumiDialog.show<bool>(
        builder: (context) => AlertDialog(
          title: const Text('导入追番备份'),
          content: Text(
            '将导入 ${parsed.items.length} 部追番，'
            '同一条目保留较新的记录。$skippedNote',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('导入'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;

      final changed = await widget.controller.importCollectibles(parsed.items);
      _toast(changed > 0 ? '已导入 $changed 部追番' : '没有需要导入的新追番');
    } on FormatException catch (error) {
      _toast(error.message);
    } catch (error) {
      KazumiLogger().w('CollectBackupPage: failed to import', error: error);
      _toast('导入失败，请重试');
    } finally {
      if (mounted) setState(() => _action = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SettingsDetailScaffold(
      title: const Text('追番备份'),
      body: Observer(
        builder: (context) {
          final count = widget.controller.collectibles.length;
          return SyncPageBody(
            maxWidth: 720,
            children: [
              const SyncPageIntro(
                icon: Icons.save_alt_rounded,
                title: '本地备份',
                description: '把追番导出到文件保存，或从文件恢复到本机。',
              ),
              SettingsSection(
                margin: EdgeInsets.zero,
                tiles: [
                  SettingsTile(
                    leading: Icons.bookmarks_rounded,
                    title: const Text('当前追番'),
                    description: Text(count == 0 ? '还没有可导出的追番' : '共 $count 部'),
                  ),
                ],
              ),
              StateActionButton(
                onPressed: _busy || count == 0 ? null : _export,
                text: _action == _BackupAction.export ? '正在导出…' : '导出到本地文件',
                icon: Icons.file_download_outlined,
              ),
              StateActionButton.tonal(
                onPressed: _busy ? null : _import,
                text: _action == _BackupAction.import ? '正在导入…' : '从本地文件导入',
                icon: Icons.file_upload_outlined,
              ),
              Text(
                '导入会与本地追番合并，同一部番剧保留更新时间较新的记录；已有条目不会被删除。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
