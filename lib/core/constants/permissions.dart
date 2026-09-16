import 'package:permission_handler/permission_handler.dart';

abstract class AppPermissions {
  static Future<void> requestAll() async {
    await [
      Permission.camera,
      Permission.microphone,
    ].request();
  }
}
