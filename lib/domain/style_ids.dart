/// Visual style ids offered in the picker (the theme layer must define each
/// of them; a test keeps both lists equal). Legacy ids stay valid for old
/// backups and open in the default Coffee style.
/// Release: one style (dark + light) — the colour palettes are gone and
/// their ids open in it.
const visualStyleIds = <String>['coffee'];

/// The palettes of 1.55–1.0.0+122, accepted from older settings.
const releaseRemovedStyleIds = <String>[
  'electric',
  'graphite',
  'harbor',
  'forest',
  'velvet',
  'royal',
  'sunset',
  'neon',
  'dusk',
  'emerald',
  'tropic',
  'twilight',
  'apricot',
];
const legacyStyleIds = <String>[
  ...releaseRemovedStyleIds,
  'gold',
  'lavender',
  'blue',
  // 1.55: styles removed from the picker; old settings open in Coffee.
  ...removedStyleIds,
];

/// Styles removed in 1.55. Still accepted from older settings and backups.
const removedStyleIds = <String>[
  'lime',
  'sage',
  'paper',
  'midnight',
  'aurora',
  'rose',
  'crimson',
  'plum',
  'wine',
  'copper',
  'sand',
  'terracotta',
];
