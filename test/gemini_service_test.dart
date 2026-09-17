import 'package:flutter_test/flutter_test.dart';
import 'package:adapt_app/core/services/gemini_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('GeminiService initial state', () {
    final service = GeminiService();
    expect(service.hasStoredImage, isFalse);
    expect(service.lastScannedImageBytes, isNull);
  });
}
