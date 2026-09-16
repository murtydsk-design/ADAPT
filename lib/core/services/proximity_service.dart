import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:proximity_sensor/proximity_sensor.dart';

class ProximityService {
  StreamSubscription<dynamic>? _proximitySubscription;
  final Stopwatch _proximityTimer = Stopwatch();

  void startListening({
    required VoidCallback onQuickWave,
    required VoidCallback onLongHover,
  }) {
    try {
      _proximitySubscription = ProximitySensor.events.listen(
        (int event) {
          if (event > 0) {
            _proximityTimer.reset();
            _proximityTimer.start();
          } else {
            _proximityTimer.stop();
            final duration = _proximityTimer.elapsedMilliseconds;

            if (duration >= 1500) {
              onLongHover();
            } else if (duration > 80) {
              onQuickWave();
            }
          }
        },
        onError: (err) {
          debugPrint("Proximity sensor error: $err");
        },
      );
    } catch (e) {
      debugPrint("Proximity listener init exception: $e");
    }
  }

  void stopListening() {
    _proximitySubscription?.cancel();
    _proximitySubscription = null;
  }
}
