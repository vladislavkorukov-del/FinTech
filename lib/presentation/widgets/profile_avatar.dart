import 'dart:io';

import 'package:flutter/material.dart' hide InputDecoration, Text;
import 'package:image_picker/image_picker.dart';

import '../controller.dart';
import '../haptics.dart';
import 'finora_orb.dart';
import 'service_badge.dart';
import '../l10n_widgets.dart';

/// 1.36: the person's picture — an emoji, Finora in a mood, a photo, or the
/// first letter of the name.
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({super.key, this.size = 56});
  final double size;

  static const emojis = [
    '😀', '😎', '🤓', '🥳', '😺', '🦊', '🐼', '🐨', '🐯', '🦁', '🐸', '🐵', //
    '🦄', '🐙', '🐳', '🌻', '🌈', '⭐', '🔥', '💎', '🚀', '🎧', '🎮', '☕',
  ];
  static const moods = [
    FinoraMood.happy,
    FinoraMood.wink,
    FinoraMood.delight,
    FinoraMood.calm,
    FinoraMood.thinking,
    FinoraMood.idea,
  ];

  @override
  Widget build(BuildContext context) {
    final p = FinanceScope.of(context).data.preferences;
    return avatar(context, p.avatar, p.userName, size);
  }

  static Widget avatar(
    BuildContext context,
    String value,
    String name,
    double size,
  ) {
    final scheme = Theme.of(context).colorScheme;
    Widget circle(Widget child, {Color? color}) => Container(
      key: const ValueKey('profile-avatar'),
      width: size,
      height: size,
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color ?? scheme.primary,
      ),
      child: child,
    );
    if (value.startsWith('emoji:')) {
      return circle(
        Text(value.substring(6), style: TextStyle(fontSize: size * .52)),
        color: scheme.surfaceContainerHighest,
      );
    }
    if (value.startsWith('mood:')) {
      final mood = FinoraMood.values
          .where((m) => m.name == value.substring(5))
          .firstOrNull;
      if (mood != null) {
        return circle(
          FinoraCharacter(size: size * .86, moods: [mood]),
          color: scheme.surfaceContainerHighest,
        );
      }
    }
    if (value.startsWith('file:')) {
      final file = File(value.substring(5));
      return circle(
        Image.file(
          file,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _letter(name, size, scheme),
        ),
      );
    }
    return circle(_letter(name, size, scheme));
  }

  static Widget _letter(String name, double size, ColorScheme scheme) => Text(
    name.trim().isEmpty ? 'F' : name.trim()[0].toUpperCase(),
    style: TextStyle(
      fontSize: size * .43,
      fontWeight: FontWeight.w700,
      color: scheme.onPrimary,
    ),
  );
}

/// Choose the picture: an emoji, Finora, a photo from the gallery, or none.
Future<void> showAvatarPicker(BuildContext context) async {
  final c = FinanceScope.of(context);
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Аватар', style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final e in ProfileAvatar.emojis)
                  InkWell(
                    key: ValueKey('avatar-emoji-$e'),
                    customBorder: const CircleBorder(),
                    onTap: () => Navigator.pop(ctx, 'emoji:$e'),
                    child: ProfileAvatar.avatar(ctx, 'emoji:$e', '', 48),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            const Text('Финора'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final m in ProfileAvatar.moods)
                  InkWell(
                    key: ValueKey('avatar-mood-${m.name}'),
                    customBorder: const CircleBorder(),
                    onTap: () => Navigator.pop(ctx, 'mood:${m.name}'),
                    child: ProfileAvatar.avatar(ctx, 'mood:${m.name}', '', 56),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            ListTile(
              key: const ValueKey('avatar-photo'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Фото из галереи'),
              onTap: () => Navigator.pop(ctx, 'photo'),
            ),
            ListTile(
              key: const ValueKey('avatar-none'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.text_fields_rounded),
              title: const Text('Первая буква имени'),
              onTap: () => Navigator.pop(ctx, ''),
            ),
          ],
        ),
      ),
    ),
  );
  if (choice == null) return;
  var value = choice;
  if (choice == 'photo') {
    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 88,
    );
    if (image == null) return;
    value = 'file:${await ServiceIconStore.importImage(image)}';
  }
  Haptics.success();
  await c.mutate(
    (d) => d.copyWith(preferences: d.preferences.copyWith(avatar: value)),
  );
}
