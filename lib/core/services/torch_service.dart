import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:torch_light/torch_light.dart';

class TorchService {
  bool _isTorchOn = false;

  bool get isTorchOn => _isTorchOn;

  Future<bool> toggleTorch([CameraController? cameraController]) async {
    try {
      if (_isTorchOn) {
        await turnOff(cameraController);
      } else {
        await turnOn(cameraController);
      }
      return _isTorchOn;
    } catch (e) {
      debugPrint("Torch toggle exception: $e");
      rethrow;
    }
  }

  Future<void> turnOn([CameraController? cameraController]) async {
    try {
      if (cameraController != null && cameraController.value.isInitialized) {
        await cameraController.setFlashMode(FlashMode.torch);
      } else {
        await TorchLight.enableTorch();
      }
      _isTorchOn = true;
    } catch (e) {
      debugPrint("Failed to turn on torch via CameraController: $e");
      try {
        await TorchLight.enableTorch();
        _isTorchOn = true;
      } catch (e2) {
        debugPrint("Fallback TorchLight.enableTorch failed: $e2");
        rethrow;
      }
    }
  }

  Future<void> turnOff([CameraController? cameraController]) async {
    try {
      if (cameraController != null && cameraController.value.isInitialized) {
        await cameraController.setFlashMode(FlashMode.off);
      } else {
        await TorchLight.disableTorch();
      }
    } catch (_) {
      try {
        await TorchLight.disableTorch();
      } catch (_) {}
    } finally {
      _isTorchOn = false;
    }
  }
}
