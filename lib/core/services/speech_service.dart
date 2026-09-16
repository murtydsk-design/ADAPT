import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

class SpeechService {
  final stt.SpeechToText _speech = stt.SpeechToText();

  bool _isListening = false;
  String _lastRecognizedWords = "";

  Timer? _speechTimeoutTimer;
  Timer? _silenceDebounceTimer;

  bool get isListening => _isListening;
  String get lastRecognizedWords => _lastRecognizedWords;

  Future<bool> init({
    required Function(String error) onError,
    required VoidCallback onDone,
  }) async {
    try {
      return await _speech.initialize(
        onError: (err) {
          debugPrint("Speech error: $err");
          onError(err.errorMsg);
          cancel();
        },
        onStatus: (status) {
          debugPrint("Speech status: $status");
          if (status == "done" || status == "notListening") {
            if (_isListening) {
              onDone();
            }
          }
        },
      );
    } catch (e) {
      debugPrint("Speech init exception: $e");
      return false;
    }
  }

  Future<void> startListening({
    required Function(String text) onResult,
    required VoidCallback onFinalized,
  }) async {
    if (_isListening) return;

    _lastRecognizedWords = "";
    _isListening = true;

    try {
      await _speech.listen(
        onResult: (result) {
          _lastRecognizedWords = result.recognizedWords;
          onResult(_lastRecognizedWords);

          _silenceDebounceTimer?.cancel();
          _silenceDebounceTimer = Timer(
            const Duration(milliseconds: 4000),
            () {
              if (_isListening && _lastRecognizedWords.trim().isNotEmpty) {
                stop();
                onFinalized();
              }
            },
          );

          if (result.finalResult) {
            stop();
            onFinalized();
          }
        },
        listenOptions: stt.SpeechListenOptions(
          listenMode: stt.ListenMode.confirmation,
          cancelOnError: true,
          partialResults: true,
        ),
      );

      _speechTimeoutTimer?.cancel();
      _speechTimeoutTimer = Timer(
        const Duration(seconds: 25),
        () {
          if (_isListening) {
            stop();
            onFinalized();
          }
        },
      );
    } catch (e) {
      debugPrint("Voice capture failed: $e");
      cancel();
    }
  }

  Future<void> stop() async {
    _speechTimeoutTimer?.cancel();
    _silenceDebounceTimer?.cancel();
    _isListening = false;
    try {
      await _speech.stop();
    } catch (e) {
      debugPrint("Speech stop exception: $e");
    }
  }

  void cancel() {
    _speechTimeoutTimer?.cancel();
    _silenceDebounceTimer?.cancel();
    _isListening = false;
    try {
      _speech.cancel();
    } catch (e) {
      debugPrint("Speech cancel exception: $e");
    }
  }
}
