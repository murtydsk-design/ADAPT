import 'package:torch_light/torch_light.dart';

class TorchService {
  bool _isTorchOn = false;

  bool get isTorchOn => _isTorchOn;

  Future<bool> toggleTorch() async {
    try {
      if (_isTorchOn) {
        await TorchLight.disableTorch();
        _isTorchOn = false;
      } else {
        await TorchLight.enableTorch();
        _isTorchOn = true;
      }
      return _isTorchOn;
    } catch (e) {
      rethrow;
    }
  }

  Future<void> turnOff() async {
    if (_isTorchOn) {
      try {
        await TorchLight.disableTorch();
      } catch (_) {}
      _isTorchOn = false;
    }
  }
}
