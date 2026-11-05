# Approved Finance branding

The original `Finance_F_5000_rub_texture_v7.png` is copied unchanged from the
user-supplied `Finance_icon_5000_rub.zip`. It is used by the centered Flutter
header, loading screen, and Android launcher. No alternate F is drawn.

Dimensions: 1254 × 1254; size: 1,876,256 bytes.
SHA-256: `1520aa31c87f3b5ee37aeed64432be9c8ca4c17bd3fd547329916906799e2388`.

The identical native copy is `android/app/src/main/res/drawable-nodpi/finance_brand.png`.
`drawable/ic_launcher.xml` references it as a filtered bitmap. Android scales the
original when displaying it; the source artwork is not cropped or recolored.
`test/brand_asset_test.dart` checks byte identity, decoding, and header centering.
