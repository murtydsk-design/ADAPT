import 'package:flutter_test/flutter_test.dart';
import 'package:adapt_app/core/services/tts_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('TtsService instance creation', () {
    final tts = TtsService();
    expect(tts, isNotNull);
  });
}
