/// An optional outside AI (Phase 6, audit item 70): only the interface,
/// turned off. Finora's answers come from her own engines on the phone; no
/// provider is built in, no key is stored, nothing is sent anywhere. If a
/// cloud model is ever offered, it must come through this seam, be off by
/// default, ask the person first and never receive raw operations — only
/// the facts the engines already computed.
abstract interface class AiProvider {
  /// A short name for settings («Локально», …).
  String get name;

  /// Whether the provider may be used now (configured and allowed).
  bool get available;

  /// Words for already computed [facts] in answer to [question]. The
  /// provider never calculates money and never sees the ledger.
  Future<String?> phrase(String question, Map<String, Object?> facts);
}

/// The only provider in the app: nothing outside the phone.
class NoAiProvider implements AiProvider {
  const NoAiProvider();
  @override
  String get name => 'Только на телефоне';
  @override
  bool get available => false;
  @override
  Future<String?> phrase(String question, Map<String, Object?> facts) async =>
      null;
}

/// The provider in use: always [NoAiProvider] in this build.
const AiProvider aiProvider = NoAiProvider();
