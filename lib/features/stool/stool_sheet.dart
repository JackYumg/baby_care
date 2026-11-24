import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/models.dart';
import '../../platform/image_store.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';

const Map<StoolColor, String> kStoolColorLabels = {
  StoolColor.yellow: '黄色',
  StoolColor.green: '绿色',
  StoolColor.brown: '棕色',
  StoolColor.black: '黑色',
  StoolColor.other: '其他',
};

const Map<StoolColor, Color> kStoolColorSwatches = {
  StoolColor.yellow: Color(0xFFE8C56A),
  StoolColor.green: Color(0xFF8FAE7B),
  StoolColor.brown: Color(0xFFA97A4F),
  StoolColor.black: Color(0xFF4A4640),
  StoolColor.other: Color(0xFFB9AFA0),
};

const List<String> kStoolConsistencies = ['稀', '糊状', '条状', '干硬'];

Future<void> showStoolSheet(
  BuildContext context,
  AppState state, {
  StoolRecord? stool,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => StoolSheet(state: state, stool: stool),
  );
}

class StoolSheet extends StatefulWidget {
  const StoolSheet({super.key, required this.state, this.stool});

  final AppState state;
  final StoolRecord? stool;

  @override
  State<StoolSheet> createState() => _StoolSheetState();
}

class _StoolSheetState extends State<StoolSheet> {
  late int _timeMs;
  StoolColor? _color;
  String? _consistency;
  String? _imagePath;
  String? _originalImagePath;
  final _noteController = TextEditingController();
  bool _saving = false;
  bool _pickingImage = false;

  bool get isEdit => widget.stool != null;

  @override
  void initState() {
    super.initState();
    final stool = widget.stool;
    _timeMs = stool?.occurredAt ?? DateTime.now().millisecondsSinceEpoch;
    _color = stool?.color;
    _consistency = stool?.consistency;
    _imagePath = stool?.imagePath;
    _originalImagePath = stool?.imagePath;
    _noteController.text = stool?.note ?? '';
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _pickImage({required bool camera}) async {
    if (_pickingImage || _saving) return;
    setState(() => _pickingImage = true);
    try {
      final path = await ImageStore.pickAndSave(
        folder: kStoolImageFolder,
        camera: camera,
      );
      // 用户取消时不提示，也不改动已有图片。
      if (path == null || !mounted) return;
      setState(() => _imagePath = path);
    } catch (error) {
      if (mounted) showErrorSnack(context, error);
    } finally {
      if (mounted) setState(() => _pickingImage = false);
    }
  }

  Future<void> _save() async {
    if (_timeMs > DateTime.now().millisecondsSinceEpoch) {
      showSuccessSnack(context, '时间不能晚于当前时间');
      return;
    }
    setState(() => _saving = true);
    try {
      final note = _noteController.text.trim().isEmpty
          ? null
          : _noteController.text.trim();
      if (isEdit) {
        await widget.state.updateStool(
          id: widget.stool!.id,
          occurredAt: _timeMs,
          color: _color,
          consistency: _consistency,
          note: note,
          imagePath: _imagePath,
        );
      } else {
        await widget.state.addStool(
          occurredAt: _timeMs,
          color: _color,
          consistency: _consistency,
          note: note,
          imagePath: _imagePath,
        );
      }
      await _deleteReplacedImage();
      if (!mounted) return;
      Navigator.of(context).pop();
      showSuccessSnack(context, isEdit ? '已保存修改' : '已记录排便');
    } catch (error) {
      if (mounted) showErrorSnack(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// 保存成功后删除被替换或移除的旧图片。
  Future<void> _deleteReplacedImage() async {
    final oldPath = _originalImagePath;
    if (oldPath == null || oldPath.isEmpty || oldPath == _imagePath) return;
    _originalImagePath = _imagePath;
    try {
      await ImageStore.delete(oldPath);
    } catch (_) {
      // 旧图片删除失败不影响已保存的记录。
    }
  }

  Widget _buildPhotoSection(BuildContext context) {
    final path = _imagePath;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('照片（可选）', style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 8),
        if (path == null || path.isEmpty)
          Row(
            children: [
              _photoPickerTile(
                icon: Icons.photo_camera_rounded,
                label: '拍照',
                onTap: () => _pickImage(camera: true),
              ),
              const SizedBox(width: 10),
              _photoPickerTile(
                icon: Icons.photo_library_rounded,
                label: '从相册选择',
                onTap: () => _pickImage(camera: false),
              ),
            ],
          )
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StoolImageThumbnail(relativePath: path, size: 96),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    const Text(
                      '点击缩略图可查看大图',
                      style: TextStyle(fontSize: 12, color: AppColors.subtle),
                    ),
                    Wrap(
                      spacing: 4,
                      children: [
                        TextButton.icon(
                          onPressed: _pickingImage
                              ? null
                              : () => _pickImage(camera: false),
                          icon: const Icon(
                            Icons.photo_library_rounded,
                            size: 18,
                          ),
                          label: const Text('更换'),
                        ),
                        TextButton.icon(
                          onPressed: _pickingImage
                              ? null
                              : () => setState(() => _imagePath = null),
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            size: 18,
                          ),
                          label: const Text('移除'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _photoPickerTile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final enabled = !_pickingImage && !_saving;
    final color = Theme.of(context).colorScheme.primary;
    final contentColor = enabled ? color : color.withValues(alpha: 0.4);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: enabled ? onTap : null,
      child: Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 24, color: contentColor),
            const SizedBox(height: 6),
            Text(label, style: TextStyle(fontSize: 11, color: contentColor)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  isEdit ? '编辑排便' : '记录排便',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TimeField(
              label: '排便时间',
              valueMs: _timeMs,
              onChanged: (value) => setState(() => _timeMs = value),
            ),
            const SizedBox(height: 18),
            _buildPhotoSection(context),
            const SizedBox(height: 18),
            Text('颜色（可选）', style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                for (final entry in kStoolColorLabels.entries)
                  ChoiceChip(
                    avatar: CircleAvatar(
                      backgroundColor: kStoolColorSwatches[entry.key],
                    ),
                    label: Text(entry.value),
                    selected: _color == entry.key,
                    onSelected: (selected) =>
                        setState(() => _color = selected ? entry.key : null),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            Text('性状（可选）', style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              children: [
                for (final item in kStoolConsistencies)
                  ChoiceChip(
                    label: Text(item),
                    selected: _consistency == item,
                    onSelected: (selected) =>
                        setState(() => _consistency = selected ? item : null),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _noteController,
              maxLength: 500,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: '备注（可选）',
                counterText: '',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(isEdit ? '保存修改' : '保存记录'),
            ),
            if (isEdit) ...[
              const SizedBox(height: 10),
              TextButton(
                onPressed: () async {
                  final ok = await showConfirmDialog(
                    context,
                    title: '删除这条排便记录？',
                    message: '删除后统计会立即更新，且无法恢复。',
                    confirmText: '删除',
                    destructive: true,
                  );
                  if (!ok) return;
                  await widget.state.deleteStool(widget.stool!.id);
                  if (!context.mounted) return;
                  Navigator.of(context).pop();
                },
                child: const Text('删除记录'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 以圆角缩略图展示应用私有目录中的图片，点击可全屏查看。
class StoolImageThumbnail extends StatefulWidget {
  const StoolImageThumbnail({
    super.key,
    required this.relativePath,
    this.size = 96,
    this.radius = 12,
  });

  /// 数据库保存的相对路径，例如 `stool/xxx.jpg`。
  final String relativePath;
  final double size;
  final double radius;

  @override
  State<StoolImageThumbnail> createState() => _StoolImageThumbnailState();
}

class _StoolImageThumbnailState extends State<StoolImageThumbnail> {
  late Future<File?> _file = ImageStore.file(widget.relativePath);

  @override
  void didUpdateWidget(covariant StoolImageThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.relativePath != widget.relativePath) {
      _file = ImageStore.file(widget.relativePath);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: GestureDetector(
        onTap: () => showStoolImagePreview(context, widget.relativePath),
        child: Container(
          width: widget.size,
          height: widget.size,
          color: AppColors.border,
          child: FutureBuilder<File?>(
            future: _file,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              }
              final file = snapshot.data;
              if (file == null) return const _ThumbnailFallback();
              return Image.file(
                file,
                width: widget.size,
                height: widget.size,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const _ThumbnailFallback(),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ThumbnailFallback extends StatelessWidget {
  const _ThumbnailFallback();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Icon(
        Icons.broken_image_outlined,
        size: 20,
        color: AppColors.subtle,
      ),
    );
  }
}

/// 全屏查看图片相对路径对应的大图。
Future<void> showStoolImagePreview(BuildContext context, String relativePath) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black87,
    builder: (_) => _ImagePreviewDialog(relativePath: relativePath),
  );
}

class _ImagePreviewDialog extends StatelessWidget {
  const _ImagePreviewDialog({required this.relativePath});

  final String relativePath;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: Stack(
        alignment: Alignment.center,
        children: [
          InteractiveViewer(
            maxScale: 4,
            child: FutureBuilder<File?>(
              future: ImageStore.file(relativePath),
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const SizedBox(
                    height: 120,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final file = snapshot.data;
                if (file == null) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      '图片不存在',
                      style: TextStyle(color: Colors.white70),
                    ),
                  );
                }
                return Image.file(
                  file,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      '图片无法打开',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                );
              },
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: IconButton(
              tooltip: '关闭',
              onPressed: () => Navigator.of(context).pop(),
              style: IconButton.styleFrom(
                backgroundColor: Colors.black45,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.close_rounded),
            ),
          ),
        ],
      ),
    );
  }
}
