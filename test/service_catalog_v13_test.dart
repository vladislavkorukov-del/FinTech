import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:finora/domain/service_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'curated catalog expands subscriptions while preserving every legacy ID',
    () {
      const legacy = <String>[
        "youtube_premium",
        "spotify",
        "netflix",
        "yandex_plus",
        "kinopoisk",
        "vk_music",
        "telegram_premium",
        "apple_music",
        "icloud",
        "google_one",
        "chatgpt",
        "okko",
        "ivi",
        "wink",
        "start",
        "kion",
        "microsoft365",
        "dropbox",
        "playstation_plus",
        "youtube_music",
        "deezer",
        "tidal",
        "twitch",
        "discord_nitro",
        "notion",
        "todoist",
        "github_copilot",
        "figma",
        "duolingo",
        "strava",
        "lastpass",
        "onepassword",
        "zoom",
        "patreon",
        "crunchyroll",
        "audible",
        "headspace",
        "mubi",
        "hbo_max",
        "paramount_plus",
        "nordvpn",
        "proton_vpn",
        "proton_drive",
        "google_drive",
        "bitwarden",
        "evernote",
        "obsidian",
        "webflow",
        "linear",
        "asana",
        "clickup",
        "vimeo",
        "soundcloud",
        "bandcamp",
        "pocket_casts",
        "overcast",
        "mega",
        "dashlane",
        "surfshark",
        "expressvpn",
        "mullvad",
        "backblaze",
      ];
      expect(ServiceCatalog.entries.length, greaterThanOrEqualTo(200));
      expect(
        ServiceCatalog.entries.map((s) => s.id).toSet().length,
        ServiceCatalog.entries.length,
      );
      for (final id in legacy) {
        expect(ServiceCatalog.byId(id), isNotNull, reason: 'Legacy ID $id');
      }
      for (final group in [
        'ai',
        'reading',
        'education',
        'telecom',
        'security',
        'games',
        'cloud',
        'music',
        'video',
      ]) {
        expect(ServiceCatalog.search('', group: group), isNotEmpty);
      }
      for (final service in ServiceCatalog.entries) {
        expect(ServiceCatalog.groups, contains(service.group));
        expect(ServiceCatalog.byName(service.name)?.id, service.id);
        expect(service.inset, inInclusiveRange(0, .4));
      }
    },
  );

  test(
    'RU and EN discovery remains case insensitive and exact legacy matching safe',
    () {
      expect(
        ServiceCatalog.search('ДЖЕМИНИ').map((s) => s.id),
        contains('gemini'),
      );
      expect(
        ServiceCatalog.search('КЛОД').map((s) => s.id),
        contains('claude'),
      );
      expect(
        ServiceCatalog.search('MAIL CLOUD').map((s) => s.id),
        contains('mail_cloud'),
      );
      expect(
        ServiceCatalog.search('КАСПЕРСКИЙ').map((s) => s.id),
        contains('kaspersky'),
      );
      expect(ServiceCatalog.byName('  NETFLIX  ')?.id, 'netflix');
      expect(ServiceCatalog.byName('яндекс книги')?.id, 'bookmate');
      expect(ServiceCatalog.byName('spotify insurance'), isNull);
      for (final custom in [
        'музыка',
        'vpn',
        'облако',
        'дизайн',
        'премиум',
        'apple',
      ]) {
        expect(ServiceCatalog.byName(custom), isNull, reason: custom);
      }
    },
  );

  test('all priority missing brands now use authentic bundled artwork', () {
    for (final id in [
      'yandex_plus',
      'okko',
      'ivi',
      'wink',
      'start',
      'kion',
      'chatgpt',
      'google_one',
      'microsoft365',
    ]) {
      final service = ServiceCatalog.byId(id)!;
      expect(service.assetPath, isNotNull, reason: id);
      expect(service.preserveColors, isTrue, reason: id);
      expect(File(service.assetPath!).existsSync(), isTrue);
    }
  });

  test('popular Russian recurring services use original provider artwork', () {
    final manifest =
        jsonDecode(File('assets/services/manifest.json').readAsStringSync())
            as Map<String, dynamic>;
    final items = (manifest['items'] as List).cast<Map<String, dynamic>>();
    for (final id in [
      'mts_premium',
      'beeline',
      't2',
      'tbank_pro',
      'ozon_premium',
      'wb_jam',
      'sberprime',
      'rutube',
      'vk_combo',
    ]) {
      final service = ServiceCatalog.byId(id)!;
      expect(service.preserveColors, isTrue);
      final source = items.singleWhere((item) => item['id'] == id);
      expect(source['sourceType'], 'wikimedia-commons');
      expect(source['providerBrand'], isTrue);
      expect(source['license']['LicenseShortName'], 'Public domain');
      expect(source['licenseNotes'], contains('trademark'));
    }
    for (final id in [
      'mts_premium',
      'tbank_pro',
      'ozon_premium',
      'wb_jam',
      'sberprime',
      'vk_combo',
    ]) {
      expect(
        items.singleWhere((item) => item['id'] == id)['parentBrand'],
        isTrue,
      );
    }
    expect(ServiceCatalog.search('ОЗОН ПРЕМИУМ').single.id, 'ozon_premium');
    expect(ServiceCatalog.byName('теле2')?.id, 't2');
  });

  test(
    'every catalog image matches its original digest and individual provenance',
    () {
      final manifest =
          jsonDecode(File('assets/services/manifest.json').readAsStringSync())
              as Map<String, dynamic>;
      final items = (manifest['items'] as List).cast<Map<String, dynamic>>();
      expect(items.length, ServiceCatalog.entries.length);
      for (final item in items) {
        final service = ServiceCatalog.byId(item['id'] as String)!;
        expect(service.assetPath, item['assetPath']);
        final path = service.assetPath!;
        expect(path, startsWith('assets/services/'));
        expect(path, isNot(contains('..')));
        final bytes = File(path).readAsBytesSync();
        expect(bytes.length, lessThanOrEqualTo(2 * 1024 * 1024));
        expect(
          sha256.convert(bytes).toString(),
          item['sha256'],
          reason: service.id,
        );
        final uri = Uri.parse(
          (item['downloadUrl'] ?? item['svgUrl']) as String,
        );
        expect(uri.scheme, 'https');
        expect(item['source'], isNotEmpty);
        expect(item['license'], isNotNull);
        if (service.preserveColors) {
          expect(item['licenseNotes'], contains('trademark'));
        } else {
          expect(item['svgUrl'], contains(manifest['sourceCommit'] as String));
        }
        if (path.endsWith('.png')) {
          expect(bytes.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
        } else if (path.endsWith('.svg')) {
          expect(utf8.decode(bytes), contains('<svg'));
        } else {
          expect(path, endsWith('.webp'));
        }
      }
    },
  );
}
