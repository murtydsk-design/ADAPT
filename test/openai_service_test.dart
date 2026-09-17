import 'package:flutter_test/flutter_test.dart';
import 'package:adapt_app/core/services/openai_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('OpenAiService initial state', () {
    final service = OpenAiService();
    expect(service.hasStoredImage, isFalse);
    expect(service.lastScannedImageBytes, isNull);
  });
}
