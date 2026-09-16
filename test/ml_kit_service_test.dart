import 'package:flutter_test/flutter_test.dart';
import 'package:adapt_app/core/services/ml_kit_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('MlKitService initialization and cleanup', () {
    final service = MlKitService();
    expect(service, isNotNull);
    service.dispose();
  });
}
