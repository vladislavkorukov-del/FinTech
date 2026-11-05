// Offline subscription metadata. Real logos and provenance: docs/SERVICE_ASSETS.md.
class SubscriptionService {
  const SubscriptionService({
    required this.id,
    required this.name,
    required this.group,
    this.aliases = const [],
    this.assetPath,
    this.color = 0xFF000000,
  });
  final String id, name, group;
  final List<String> aliases;
  final String? assetPath;
  final int color;
}

abstract final class ServiceCatalog {
  static const groups = <String, String>{
    'video': 'Кино и видео',
    'music': 'Музыка и подкасты',
    'cloud': 'Облако',
    'productivity': 'Работа и учёба',
    'security': 'Безопасность',
    'games': 'Игры',
    'other': 'Другие',
  };
  static const entries = <SubscriptionService>[
    SubscriptionService(
      id: "youtube_premium",
      name: "YouTube Premium",
      group: "video",
      aliases: ["ютуб", "ютюб", "премиум", "youtube premium"],
      assetPath: "assets/services/youtube.svg",
      color: 0xFFFF0000,
    ),
    SubscriptionService(
      id: "spotify",
      name: "Spotify",
      group: "music",
      aliases: ["спотифай", "споти", "музыка"],
      assetPath: "assets/services/spotify.svg",
      color: 0xFF1ED760,
    ),
    SubscriptionService(
      id: "netflix",
      name: "Netflix",
      group: "video",
      aliases: ["нетфликс", "нетфликc", "кино"],
      assetPath: "assets/services/netflix.svg",
      color: 0xFFE50914,
    ),
    SubscriptionService(
      id: "yandex_plus",
      name: "Яндекс Плюс",
      group: "other",
      aliases: ["yandex plus", "яндекс плюс", "яндекс+", "yandex+"],
    ),
    SubscriptionService(
      id: "kinopoisk",
      name: "Кинопоиск",
      group: "video",
      aliases: ["kinopoisk", "кино поиск"],
      assetPath: "assets/services/kinopoisk.svg",
      color: 0xFFFF5500,
    ),
    SubscriptionService(
      id: "vk_music",
      name: "VK Музыка",
      group: "music",
      aliases: ["vk music", "вк", "вконтакте", "вк музыка"],
      assetPath: "assets/services/vk.svg",
      color: 0xFF0077FF,
    ),
    SubscriptionService(
      id: "telegram_premium",
      name: "Telegram Premium",
      group: "other",
      aliases: ["телеграм", "телеграм премиум", "телега", "telegram"],
      assetPath: "assets/services/telegram.svg",
      color: 0xFF26A5E4,
    ),
    SubscriptionService(
      id: "apple_music",
      name: "Apple Music",
      group: "music",
      aliases: ["эппл мьюзик", "эпл музыка", "apple"],
      assetPath: "assets/services/applemusic.svg",
      color: 0xFFFA243C,
    ),
    SubscriptionService(
      id: "icloud",
      name: "iCloud+",
      group: "cloud",
      aliases: ["айклауд", "icloud", "apple cloud"],
      assetPath: "assets/services/icloud.svg",
      color: 0xFF3693F3,
    ),
    SubscriptionService(
      id: "google_one",
      name: "Google One",
      group: "cloud",
      aliases: ["гугл ван", "гугл облако", "google one"],
    ),
    SubscriptionService(
      id: "chatgpt",
      name: "ChatGPT",
      group: "productivity",
      aliases: ["чатгпт", "чат гпт", "openai", "чат джипити"],
    ),
    SubscriptionService(
      id: "okko",
      name: "Okko",
      group: "video",
      aliases: ["окко", "окко кино"],
    ),
    SubscriptionService(
      id: "ivi",
      name: "Иви",
      group: "video",
      aliases: ["ivi", "иви"],
    ),
    SubscriptionService(
      id: "wink",
      name: "Wink",
      group: "video",
      aliases: ["винк", "ростелеком"],
    ),
    SubscriptionService(
      id: "start",
      name: "START",
      group: "video",
      aliases: ["старт", "start"],
    ),
    SubscriptionService(
      id: "kion",
      name: "KION",
      group: "video",
      aliases: ["кион", "мтс кино"],
    ),
    SubscriptionService(
      id: "microsoft365",
      name: "Microsoft 365",
      group: "productivity",
      aliases: ["майкрософт", "office", "офис", "microsoft365", "ms365"],
    ),
    SubscriptionService(
      id: "dropbox",
      name: "Dropbox",
      group: "cloud",
      aliases: ["дропбокс", "облако"],
      assetPath: "assets/services/dropbox.svg",
      color: 0xFF0061FF,
    ),
    SubscriptionService(
      id: "playstation_plus",
      name: "PlayStation Plus",
      group: "games",
      aliases: ["плейстейшн", "ps plus", "psplus", "sony", "пс плюс"],
      assetPath: "assets/services/playstation.svg",
      color: 0xFF0070D1,
    ),
    SubscriptionService(
      id: "youtube_music",
      name: "YouTube Music",
      group: "music",
      aliases: ["ютуб музыка", "ютюб музыка", "youtube music"],
      assetPath: "assets/services/youtubemusic.svg",
      color: 0xFFFF0000,
    ),
    SubscriptionService(
      id: "deezer",
      name: "Deezer",
      group: "music",
      aliases: ["дизер", "музыка"],
      assetPath: "assets/services/deezer.svg",
      color: 0xFFA238FF,
    ),
    SubscriptionService(
      id: "tidal",
      name: "TIDAL",
      group: "music",
      aliases: ["тайдал", "тидал"],
      assetPath: "assets/services/tidal.svg",
      color: 0xFF000000,
    ),
    SubscriptionService(
      id: "twitch",
      name: "Twitch",
      group: "video",
      aliases: ["твич", "стримы"],
      assetPath: "assets/services/twitch.svg",
      color: 0xFF9146FF,
    ),
    SubscriptionService(
      id: "discord_nitro",
      name: "Discord Nitro",
      group: "other",
      aliases: ["дискорд", "нитро", "discord"],
      assetPath: "assets/services/discord.svg",
      color: 0xFF5865F2,
    ),
    SubscriptionService(
      id: "notion",
      name: "Notion",
      group: "productivity",
      aliases: ["ноушен", "нотион", "заметки"],
      assetPath: "assets/services/notion.svg",
      color: 0xFF000000,
    ),
    SubscriptionService(
      id: "todoist",
      name: "Todoist",
      group: "productivity",
      aliases: ["тудуист", "тодоист", "задачи"],
      assetPath: "assets/services/todoist.svg",
      color: 0xFFE44332,
    ),
    SubscriptionService(
      id: "github_copilot",
      name: "GitHub Copilot",
      group: "productivity",
      aliases: ["гитхаб", "копилот", "github", "разработка"],
      assetPath: "assets/services/githubcopilot.svg",
      color: 0xFF000000,
    ),
    SubscriptionService(
      id: "figma",
      name: "Figma",
      group: "productivity",
      aliases: ["фигма", "дизайн"],
      assetPath: "assets/services/figma.svg",
      color: 0xFFF24E1E,
    ),
    SubscriptionService(
      id: "duolingo",
      name: "Duolingo",
      group: "other",
      aliases: ["дуолинго", "языки"],
      assetPath: "assets/services/duolingo.svg",
      color: 0xFF58CC02,
    ),
    SubscriptionService(
      id: "strava",
      name: "Strava",
      group: "other",
      aliases: ["страва", "спорт"],
      assetPath: "assets/services/strava.svg",
      color: 0xFFFC4C02,
    ),
    SubscriptionService(
      id: "lastpass",
      name: "LastPass",
      group: "security",
      aliases: ["ластпасс", "пароли"],
      assetPath: "assets/services/lastpass.svg",
      color: 0xFFD32D27,
    ),
    SubscriptionService(
      id: "onepassword",
      name: "1Password",
      group: "security",
      aliases: ["ванпассворд", "один пароль", "пароли"],
      assetPath: "assets/services/1password.svg",
      color: 0xFF145FE4,
    ),
    SubscriptionService(
      id: "zoom",
      name: "Zoom",
      group: "productivity",
      aliases: ["зум", "видеосвязь"],
      assetPath: "assets/services/zoom.svg",
      color: 0xFF0B5CFF,
    ),
    SubscriptionService(
      id: "patreon",
      name: "Patreon",
      group: "other",
      aliases: ["патреон", "авторы"],
      assetPath: "assets/services/patreon.svg",
      color: 0xFF000000,
    ),
    SubscriptionService(
      id: "crunchyroll",
      name: "Crunchyroll",
      group: "video",
      aliases: ["кранчиролл", "аниме"],
      assetPath: "assets/services/crunchyroll.svg",
      color: 0xFFFF5E00,
    ),
    SubscriptionService(
      id: "audible",
      name: "Audible",
      group: "other",
      aliases: ["одибл", "аудиокниги", "amazon audible"],
      assetPath: "assets/services/audible.svg",
      color: 0xFFF8991C,
    ),
    SubscriptionService(
      id: "headspace",
      name: "Headspace",
      group: "other",
      aliases: ["хэдспейс", "медитация"],
      assetPath: "assets/services/headspace.svg",
      color: 0xFFF47D31,
    ),
    SubscriptionService(
      id: "mubi",
      name: "MUBI",
      group: "video",
      aliases: ["муби", "кино"],
      assetPath: "assets/services/mubi.svg",
      color: 0xFF000000,
    ),
    SubscriptionService(
      id: "hbo_max",
      name: "HBO Max",
      group: "video",
      aliases: ["эйчбио", "макс", "hbo"],
      assetPath: "assets/services/hbomax.svg",
      color: 0xFF000000,
    ),
    SubscriptionService(
      id: "paramount_plus",
      name: "Paramount+",
      group: "video",
      aliases: ["парамаунт", "paramount"],
      assetPath: "assets/services/paramountplus.svg",
      color: 0xFF0064FF,
    ),
    SubscriptionService(
      id: "nordvpn",
      name: "NordVPN",
      group: "security",
      aliases: ["норд впн", "норд", "vpn"],
      assetPath: "assets/services/nordvpn.svg",
      color: 0xFF4687FF,
    ),
    SubscriptionService(
      id: "proton_vpn",
      name: "Proton VPN",
      group: "security",
      aliases: ["протон впн", "protonvpn", "vpn"],
      assetPath: "assets/services/protonvpn.svg",
      color: 0xFF66DEB1,
    ),
    SubscriptionService(
      id: "proton_drive",
      name: "Proton Drive",
      group: "cloud",
      aliases: ["протон драйв", "proton cloud"],
      assetPath: "assets/services/protondrive.svg",
      color: 0xFFEB508D,
    ),
    SubscriptionService(
      id: "google_drive",
      name: "Google Drive",
      group: "cloud",
      aliases: ["гугл диск", "google диск", "gdrive"],
      assetPath: "assets/services/googledrive.svg",
      color: 0xFF4285F4,
    ),
    SubscriptionService(
      id: "bitwarden",
      name: "Bitwarden",
      group: "security",
      aliases: ["битварден", "пароли"],
      assetPath: "assets/services/bitwarden.svg",
      color: 0xFF175DDC,
    ),
    SubscriptionService(
      id: "evernote",
      name: "Evernote",
      group: "productivity",
      aliases: ["эверноут", "заметки"],
      assetPath: "assets/services/evernote.svg",
      color: 0xFF00A82D,
    ),
    SubscriptionService(
      id: "obsidian",
      name: "Obsidian",
      group: "productivity",
      aliases: ["обсидиан", "заметки"],
      assetPath: "assets/services/obsidian.svg",
      color: 0xFF7C3AED,
    ),
    SubscriptionService(
      id: "webflow",
      name: "Webflow",
      group: "productivity",
      aliases: ["вебфлоу", "сайты"],
      assetPath: "assets/services/webflow.svg",
      color: 0xFF146EF5,
    ),
    SubscriptionService(
      id: "linear",
      name: "Linear",
      group: "productivity",
      aliases: ["линеар", "задачи"],
      assetPath: "assets/services/linear.svg",
      color: 0xFF5E6AD2,
    ),
    SubscriptionService(
      id: "asana",
      name: "Asana",
      group: "productivity",
      aliases: ["асана", "задачи"],
      assetPath: "assets/services/asana.svg",
      color: 0xFFF06A6A,
    ),
    SubscriptionService(
      id: "clickup",
      name: "ClickUp",
      group: "productivity",
      aliases: ["кликап", "задачи"],
      assetPath: "assets/services/clickup.svg",
      color: 0xFF7B68EE,
    ),
    SubscriptionService(
      id: "vimeo",
      name: "Vimeo",
      group: "video",
      aliases: ["вимео", "видео"],
      assetPath: "assets/services/vimeo.svg",
      color: 0xFF1AB7EA,
    ),
    SubscriptionService(
      id: "soundcloud",
      name: "SoundCloud Go+",
      group: "music",
      aliases: ["саундклауд", "soundcloud", "музыка"],
      assetPath: "assets/services/soundcloud.svg",
      color: 0xFFFF5500,
    ),
    SubscriptionService(
      id: "bandcamp",
      name: "Bandcamp",
      group: "music",
      aliases: ["бэндкемп", "бандкамп"],
      assetPath: "assets/services/bandcamp.svg",
      color: 0xFF408294,
    ),
    SubscriptionService(
      id: "pocket_casts",
      name: "Pocket Casts",
      group: "music",
      aliases: ["покет кастс", "подкасты"],
      assetPath: "assets/services/pocketcasts.svg",
      color: 0xFFF43E37,
    ),
    SubscriptionService(
      id: "overcast",
      name: "Overcast",
      group: "music",
      aliases: ["оверкаст", "подкасты"],
      assetPath: "assets/services/overcast.svg",
      color: 0xFFFC7E0F,
    ),
    SubscriptionService(
      id: "mega",
      name: "MEGA",
      group: "cloud",
      aliases: ["мега облако", "облако"],
      assetPath: "assets/services/mega.svg",
      color: 0xFFD9272E,
    ),
    SubscriptionService(
      id: "dashlane",
      name: "Dashlane",
      group: "security",
      aliases: ["дэшлейн", "пароли"],
      assetPath: "assets/services/dashlane.svg",
      color: 0xFF0E353D,
    ),
    SubscriptionService(
      id: "surfshark",
      name: "Surfshark",
      group: "security",
      aliases: ["серфшарк", "сёрфшарк", "vpn"],
      assetPath: "assets/services/surfshark.svg",
      color: 0xFF1EBFBF,
    ),
    SubscriptionService(
      id: "expressvpn",
      name: "ExpressVPN",
      group: "security",
      aliases: ["экспресс впн", "vpn"],
      assetPath: "assets/services/expressvpn.svg",
      color: 0xFFDA3940,
    ),
    SubscriptionService(
      id: "mullvad",
      name: "Mullvad VPN",
      group: "security",
      aliases: ["муллвад", "мульвад", "vpn"],
      assetPath: "assets/services/mullvad.svg",
      color: 0xFF294D73,
    ),
    SubscriptionService(
      id: "backblaze",
      name: "Backblaze",
      group: "cloud",
      aliases: ["бэкблейз", "резервная копия"],
      assetPath: "assets/services/backblaze.svg",
      color: 0xFFE21E29,
    ),
  ];
  static SubscriptionService? byId(String? id) {
    for (final service in entries) {
      if (service.id == id) return service;
    }
    return null;
  }

  // Search keywords such as "music" are useful discovery terms, never proof
  // that an existing custom subscription belongs to a particular brand.
  static const _searchOnlyAliases = <String>{
    'музыка',
    'кино',
    'облако',
    'заметки',
    'задачи',
    'разработка',
    'дизайн',
    'языки',
    'спорт',
    'пароли',
    'видеосвязь',
    'авторы',
    'аниме',
    'аудиокниги',
    'медитация',
    'vpn',
    'подкасты',
    'резервная копия',
    'сайты',
    'видео',
    'стримы',
    'премиум',
    'apple',
  };
  static SubscriptionService? byName(String? name) {
    if (name == null || _normalize(name).isEmpty) return null;
    final wanted = _normalize(name);
    final found = entries
        .where(
          (service) =>
              _normalize(service.name) == wanted ||
              service.aliases.any(
                (alias) =>
                    !_searchOnlyAliases.contains(_normalize(alias)) &&
                    _normalize(alias) == wanted,
              ),
        )
        .toList();
    return found.length == 1 ? found.single : null;
  }

  static String _normalize(String value) => value
      .toLowerCase()
      .replaceAll('ё', 'е')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  static List<SubscriptionService> search(String query, {String? group}) {
    final terms = _normalize(
      query,
    ).split(" ").where((s) => s.isNotEmpty).toList();
    return entries.where((service) {
      if (group != null && service.group != group) return false;
      final haystack = _normalize(
        [service.name, service.id, ...service.aliases].join(" "),
      );
      return terms.every(haystack.contains);
    }).toList();
  }
}
