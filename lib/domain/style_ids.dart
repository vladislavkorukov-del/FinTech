/// Visual style ids offered in the picker (the theme layer must define each
/// of them; a test keeps both lists equal). Legacy ids stay valid for old
/// backups and open in the default Coffee style.
const visualStyleIds = <String>[
  'coffee',
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
