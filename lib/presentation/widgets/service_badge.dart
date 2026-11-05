import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../domain/service_catalog.dart';
import 'common.dart';
import 'service_logo_image.dart';

class ServiceSelection {
  const ServiceSelection({
    required this.name,
    this.serviceId,
    this.customIconPath,
  });
  final String name;
  final String? serviceId;
  final String? customIconPath;
}

/// Real, bundled service marks; unidentified services use a neutral glyph.
/// Brand colors remain the source artwork's colors on a neutral contrast plate.
class ServiceBadge extends StatefulWidget {
  const ServiceBadge({
    super.key,
    this.serviceId,
    this.customIconPath,
    this.name,
    this.size = 44,
  });
  final String? serviceId, customIconPath, name;
  final double size;

  @override
  State<ServiceBadge> createState() => _ServiceBadgeState();
}

class _ServiceBadgeState extends State<ServiceBadge> {
  String? _failedCustomPath;

  void _customFailed(String path) {
    // Image.errorBuilder runs during build. Rebuild the entire plate on the
    // next frame so its colors and inset also revert to the correct brand.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          widget.customIconPath == path &&
          _failedCustomPath != path) {
        setState(() => _failedCustomPath = path);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final serviceId = widget.serviceId;
    final customIconPath = widget.customIconPath;
    final name = widget.name;
    final size = widget.size;
    final service =
        ServiceCatalog.byId(serviceId) ?? ServiceCatalog.byName(name);
    final scheme = Theme.of(context).colorScheme;
    final uploaded =
        (customIconPath?.isNotEmpty ?? false) &&
        customIconPath != _failedCustomPath;
    final asset = service?.renderAssetPath;
    final fallback = Icon(
      Icons.subscriptions_outlined,
      color: scheme.onSurfaceVariant,
      size: size * .48,
    );
    final inset = uploaded ? .06 : (service?.inset ?? .18).clamp(0.0, .4);
    final pixels = serviceLogoDecodeSize(
      size * (1 - 2 * inset),
      MediaQuery.devicePixelRatioOf(context),
    );
    final ImageProvider? image = uploaded
        ? ResizeImage(
            FileImage(File(customIconPath!)),
            width: pixels,
            height: pixels,
            policy: ResizeImagePolicy.fit,
          )
        : asset == null
        ? null
        : ResizeImage(
            AssetImage(asset),
            width: pixels,
            height: pixels,
            policy: ResizeImagePolicy.fit,
          );
    final radius = BorderRadius.circular(size * .30);
    return Semantics(
      label: name ?? service?.name ?? 'Сервис',
      image: true,
      child: Container(
        key: ValueKey('service-badge-${service?.id ?? 'custom'}'),
        width: size,
        height: size,
        padding: EdgeInsets.all(size * inset),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: !uploaded && asset != null
              ? Color(service!.background)
              : scheme.surfaceContainerHighest,
          borderRadius: radius,
        ),
        foregroundDecoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: .2),
          ),
        ),
        child: image != null
            ? Image(
                image: image,
                fit: BoxFit.contain,
                isAntiAlias: true,
                filterQuality: FilterQuality.high,
                color: !uploaded && service?.preserveColors == false
                    ? Color(service!.color)
                    : null,
                colorBlendMode: BlendMode.srcIn,
                excludeFromSemantics: true,
                errorBuilder: (_, _, _) {
                  if (uploaded) _customFailed(customIconPath!);
                  return fallback;
                },
              )
            : fallback,
      ),
    );
  }
}

/// Copies a user-selected image unchanged into application-owned storage.
/// Decoding metadata bounds compressed images before they reach a finance list.
abstract final class ServiceIconStore {
  static const maxBytes = 2 * 1024 * 1024;
  static Future<String> importImage(XFile image, {Directory? directory}) async {
    final length = await image.length();
    if (length == 0 || length > maxBytes) {
      throw const FormatException('Выберите изображение размером до 2 МБ.');
    }
    final bytes = await image.readAsBytes();
    if (bytes.isEmpty || bytes.length > maxBytes) {
      throw const FormatException('Выберите изображение размером до 2 МБ.');
    }
    String extension;
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4e &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0d &&
        bytes[5] == 0x0a &&
        bytes[6] == 0x1a &&
        bytes[7] == 0x0a) {
      extension = 'png';
    } else if (bytes.length >= 3 &&
        bytes[0] == 0xff &&
        bytes[1] == 0xd8 &&
        bytes[2] == 0xff) {
      extension = 'jpg';
    } else if (bytes.length >= 12 &&
        String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
        String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') {
      extension = 'webp';
    } else {
      throw const FormatException('Поддерживаются PNG, JPEG и WebP.');
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    try {
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      try {
        if (descriptor.width > 8192 ||
            descriptor.height > 8192 ||
            descriptor.width * descriptor.height > 16000000) {
          throw const FormatException(
            'Изображение слишком большое. Выберите иконку не более 16 мегапикселей.',
          );
        }
      } finally {
        descriptor.dispose();
      }
    } finally {
      buffer.dispose();
    }
    final support = directory ?? await getApplicationSupportDirectory();
    final icons = Directory('${support.path}/service_icons');
    await icons.create(recursive: true);
    final target = File('${icons.path}/${const Uuid().v4()}.$extension');
    await target.writeAsBytes(bytes, flush: true);
    return target.path;
  }
}

Future<String?> pickServiceIcon() async {
  final image = await ImagePicker().pickImage(source: ImageSource.gallery);
  if (image == null) return null;
  return ServiceIconStore.importImage(image);
}

Future<ServiceSelection?> showServicePicker(
  BuildContext context, {
  Future<String?> Function()? pickCustomIcon,
}) => showModalBottomSheet<ServiceSelection>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) =>
      _ServicePicker(pickCustomIcon: pickCustomIcon ?? pickServiceIcon),
);

class _ServicePicker extends StatefulWidget {
  const _ServicePicker({required this.pickCustomIcon});
  final Future<String?> Function() pickCustomIcon;
  @override
  State<_ServicePicker> createState() => _ServicePickerState();
}

class _ServicePickerState extends State<_ServicePicker> {
  String query = '';
  String? group;
  @override
  Widget build(BuildContext context) {
    final results = ServiceCatalog.search(query, group: group);
    final available =
        MediaQuery.sizeOf(context).height -
        MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: math.max(160.0, available * .86),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: Text(
                'Выберите сервис',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            Expanded(
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(
                            key: const ValueKey('service-search'),
                            decoration: const InputDecoration(
                              prefixIcon: Icon(Icons.search_rounded),
                              hintText: 'Название на русском или английском',
                            ),
                            onChanged: (v) => setState(() => query = v),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '${results.length} сервисов',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 8),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                ChoiceChip(
                                  label: const Text('Все'),
                                  selected: group == null,
                                  onSelected: (_) =>
                                      setState(() => group = null),
                                ),
                                ...ServiceCatalog.groups.entries.map(
                                  (e) => Padding(
                                    padding: const EdgeInsets.only(left: 8),
                                    child: ChoiceChip(
                                      label: Text(e.value),
                                      selected: group == e.key,
                                      onSelected: (_) =>
                                          setState(() => group = e.key),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            key: const ValueKey('custom-service'),
                            icon: const Icon(
                              Icons.add_photo_alternate_outlined,
                            ),
                            label: const Text('Свой сервис'),
                            onPressed: () async {
                              final selection =
                                  await showModalBottomSheet<ServiceSelection>(
                                    context: context,
                                    isScrollControlled: true,
                                    useSafeArea: true,
                                    builder: (_) => _CustomServiceEditor(
                                      pickIcon: widget.pickCustomIcon,
                                    ),
                                  );
                              if (selection != null && context.mounted) {
                                Navigator.pop(context, selection);
                              }
                            },
                          ),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  ),
                  if (results.isEmpty)
                    const SliverToBoxAdapter(
                      child: EmptyState(
                        'Сервис не найден',
                        'Добавьте свой сервис с названием и иконкой.',
                      ),
                    ),
                  SliverList.builder(
                    itemCount: results.length,
                    itemBuilder: (_, index) {
                      final item = results[index];
                      return ListTile(
                        key: ValueKey('service-option-${item.id}'),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 5,
                        ),
                        leading: ServiceBadge(serviceId: item.id),
                        title: Text(
                          item.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(ServiceCatalog.groups[item.group]!),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => Navigator.pop(
                          context,
                          ServiceSelection(serviceId: item.id, name: item.name),
                        ),
                      );
                    },
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 24)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomServiceEditor extends StatefulWidget {
  const _CustomServiceEditor({required this.pickIcon});
  final Future<String?> Function() pickIcon;
  @override
  State<_CustomServiceEditor> createState() => _CustomServiceEditorState();
}

class _CustomServiceEditorState extends State<_CustomServiceEditor> {
  final name = TextEditingController();
  final form = GlobalKey<FormState>();
  String? iconPath;
  bool busy = false;
  bool selected = false;
  @override
  void dispose() {
    name.dispose();
    if (!selected && iconPath != null) unawaited(_deleteUnused(iconPath!));
    super.dispose();
  }

  Future<void> _deleteUnused(String path) async {
    if (p.basename(p.dirname(path)) != 'service_icons') return;
    try {
      await File(path).delete();
    } on FileSystemException {
      /* Already removed. */
    }
  }

  Future<void> _chooseIcon() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final path = await widget.pickIcon();
      if (path != null) {
        if (!mounted) {
          await _deleteUnused(path);
          return;
        }
        final old = iconPath;
        setState(() => iconPath = path);
        if (old != null && old != path) await _deleteUnused(old);
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
      child: Form(
        key: form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Свой сервис',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 20),
            Center(
              child: ServiceBadge(
                customIconPath: iconPath,
                name: name.text,
                size: 72,
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: const ValueKey('custom-service-name'),
              controller: name,
              maxLength: 80,
              decoration: const InputDecoration(labelText: 'Название сервиса'),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Введите название' : null,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const ValueKey('upload-service-icon'),
              onPressed: busy ? null : _chooseIcon,
              icon: const Icon(Icons.photo_library_outlined),
              label: Text(busy ? 'Загрузка…' : 'Загрузить иконку'),
            ),
            const SizedBox(height: 18),
            FilledButton(
              key: const ValueKey('confirm-custom-service'),
              onPressed: busy
                  ? null
                  : () {
                      if (!form.currentState!.validate()) return;
                      selected = true;
                      Navigator.pop(
                        context,
                        ServiceSelection(
                          name: name.text.trim(),
                          customIconPath: iconPath,
                        ),
                      );
                    },
              child: const Text('Выбрать'),
            ),
          ],
        ),
      ),
    ),
  );
}
