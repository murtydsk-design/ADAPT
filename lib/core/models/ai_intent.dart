enum AiIntent {
  color('COLOR'),
  price('PRICE'),
  textContent('TEXT_CONTENT'),
  objectIdentification('OBJECT_IDENTIFICATION'),
  location('LOCATION'),
  brand('BRAND'),
  quantity('QUANTITY'),
  objectState('OBJECT_STATE'),
  personPresence('PERSON_PRESENCE'),
  generalQuestion('GENERAL_QUESTION'),
  unknown('UNKNOWN');

  final String label;
  const AiIntent(this.label);

  static AiIntent parse(String rawText) {
    final cleaned = rawText
        .replaceAll(RegExp(r'[^A-Za-z0-9_ ]'), '')
        .trim()
        .toUpperCase();

    for (final intent in AiIntent.values) {
      if (cleaned.contains(intent.label)) {
        return intent;
      }
    }
    return AiIntent.generalQuestion;
  }
}
