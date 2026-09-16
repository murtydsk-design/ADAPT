import 'package:flutter_test/flutter_test.dart';
import 'package:adapt_app/core/services/gemini_service.dart';

void main() {
  group('GeminiService Tests', () {
    test('GeminiService initial state', () {
      final service = GeminiService();
      expect(service.hasStoredImage, isFalse);
      expect(service.lastScannedImageBytes, isNull);
    });

    test('GeminiService clearConversation resets state', () {
      final service = GeminiService();
      service.clearConversation();
      expect(service.hasStoredImage, isFalse);
      expect(service.lastScannedImageBytes, isNull);
    });
  });
}
