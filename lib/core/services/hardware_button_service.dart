import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../constants/hardware_channels.dart';

class HardwareButtonService {
  static const EventChannel _buttonChannel =
      EventChannel(HardwareChannels.buttonEventChannel);

  static const MethodChannel _switchChannel =
      MethodChannel(HardwareChannels.switchMethodChannel);

  StreamSubscription<dynamic>? _buttonSubscription;

  final Stopwatch _holdTimer = Stopwatch();
  final Stopwatch _downPressTimer = Stopwatch();

  DateTime? _lastDownClickTime;
  Timer? _singleClickDebounceTimer;

  bool isMediaVolumeUnlocked = false;

  void startListening({
    required VoidCallback onVolumeUpRelease,
    required VoidCallback onVolumeDownSingleClick,
    required VoidCallback onVolumeDownLongPress,
    required VoidCallback onVolumeDownDoubleClick,
    required Function(bool isMediaUnlocked) onMediaVolumeToggle,
  }) {
    _buttonSubscription = _buttonChannel.receiveBroadcastStream().listen(
      (dynamic event) {
        final String action = event.toString();

        if (action.contains("PRESSED")) {
          _holdTimer.reset();
          _holdTimer.start();

          if (action == "DOWN_PRESSED") {
            _downPressTimer.reset();
            _downPressTimer.start();
          }
        } else if (action.contains("RELEASED")) {
          _holdTimer.stop();

          if (action == "DOWN_RELEASED") {
            _downPressTimer.stop();
            final downHoldDuration = _downPressTimer.elapsedMilliseconds;

            if (downHoldDuration >= 800) {
              onVolumeDownLongPress();
              return;
            }
          }

          if (_holdTimer.elapsedMilliseconds > 3000 && action == "UP_RELEASED") {
            isMediaVolumeUnlocked = !isMediaVolumeUnlocked;
            setMediaInterception(!isMediaVolumeUnlocked);
            onMediaVolumeToggle(isMediaVolumeUnlocked);
          } else {
            if (!isMediaVolumeUnlocked) {
              if (action == "UP_RELEASED") {
                onVolumeUpRelease();
              } else if (action == "DOWN_RELEASED") {
                _handleDownRelease(
                  onSingleClick: onVolumeDownSingleClick,
                  onDoubleClick: onVolumeDownDoubleClick,
                );
              }
            }
          }
        }
      },
      onError: (err) {
        debugPrint("Hardware button stream error: $err");
      },
    );
  }

  void _handleDownRelease({
    required VoidCallback onSingleClick,
    required VoidCallback onDoubleClick,
  }) {
    final now = DateTime.now();

    if (_lastDownClickTime != null &&
        now.difference(_lastDownClickTime!).inMilliseconds < 500) {
      _singleClickDebounceTimer?.cancel();
      _lastDownClickTime = null;
      onDoubleClick();
      return;
    }

    _lastDownClickTime = now;
    _singleClickDebounceTimer?.cancel();
    _singleClickDebounceTimer = Timer(
      const Duration(milliseconds: 500),
      () {
        onSingleClick();
      },
    );
  }

  Future<void> setMediaInterception(bool intercept) async {
    try {
      await _switchChannel.invokeMethod('setInterception', {
        'intercept': intercept,
      });
    } catch (e) {
      debugPrint("Error setting media interception: $e");
    }
  }

  void dispose() {
    _singleClickDebounceTimer?.cancel();
    _buttonSubscription?.cancel();
  }
}
