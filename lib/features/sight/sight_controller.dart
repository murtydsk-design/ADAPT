import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:vibration/vibration.dart';
import '../../core/models/ai_intent.dart';
import '../../core/services/camera_service.dart';
import '../../core/services/gemini_service.dart';
import '../../core/services/speech_service.dart';
import '../../core/services/torch_service.dart';
import '../../core/services/tts_service.dart';
import '../../core/utils/image_compressor.dart';

class SightController {
  final CameraService cameraService;
  final GeminiService geminiService;
  final TorchService torchService;
  final SpeechService speechService;
  final TtsService ttsService;

  int _sightToolIndex = 0;
  final List<String> _sightTools = [
    "Item Scanner",
    "Document Reader",
    "Torch Light"
  ];

  bool isLocked = false;
  bool isProcessingAi = false;
  bool isListeningSpeech = false;

  // Request lock to prevent duplicate concurrent AI calls
  bool _isAiRequestInProgress = false;

  String _fullGeminiResponse = "";
  String get fullGeminiResponse => _fullGeminiResponse;

  String activeActionStatus = "Initializing...";

  // Document Guidance Stream
  bool _isAnalyzingStream = false;
  int _documentStabilityScore = 0;
  DateTime _lastGuidanceNotification = DateTime.now();

  SightController({
    required this.cameraService,
    required this.geminiService,
    required this.torchService,
    required this.speechService,
    required this.ttsService,
  });

  int get sightToolIndex => _sightToolIndex;
  List<String> get sightTools => List.unmodifiable(_sightTools);
  String get currentToolName => _sightTools[_sightToolIndex];

  Future<void> lockMode({required VoidCallback onStateChanged}) async {
    isLocked = true;
    _fullGeminiResponse = "";
    try {
      await cameraService.initCamera();
      activeActionStatus = "Sight: $currentToolName";
      await ttsService.speak("Sight mode locked. $currentToolName ready.");
    } catch (e) {
      activeActionStatus = "Camera Error: $e";
      await ttsService.speak("Camera initialisation failed.");
    }
    onStateChanged();
    evaluateStreamRequirement(onStateChanged: onStateChanged);
  }

  Future<void> unlockMode({required VoidCallback onStateChanged}) async {
    isLocked = false;
    _fullGeminiResponse = "";
    cancelVoiceQuestion(onStateChanged: onStateChanged);
    geminiService.clearConversation();
    await torchService.turnOff(cameraService.controller);
    await cameraService.disposeCamera();
    onStateChanged();
  }

  void cycleSightTool({required VoidCallback onStateChanged}) {
    if (isProcessingAi || isListeningSpeech) return;

    _fullGeminiResponse = "";
    geminiService.clearConversation();
    _sightToolIndex = (_sightToolIndex + 1) % _sightTools.length;
    activeActionStatus = "Sight: $currentToolName";

    Vibration.vibrate(duration: 60);
    ttsService.speak(currentToolName);

    onStateChanged();
    evaluateStreamRequirement(onStateChanged: onStateChanged);
  }

  void executeSightToolAction({required VoidCallback onStateChanged}) {
    switch (_sightToolIndex) {
      case 0:
        scanScene(onStateChanged: onStateChanged);
        break;
      case 1:
        scanDocument(onStateChanged: onStateChanged);
        break;
      case 2:
        toggleTorch(onStateChanged: onStateChanged);
        break;
    }
  }

  /// Item Scanner: Capture 1 image, optimize, send Gemini Vision Request
  Future<void> scanScene({required VoidCallback onStateChanged}) async {
    if (_isAiRequestInProgress || !cameraService.isInitialized) return;

    await cameraService.stopStream();

    _isAiRequestInProgress = true;
    isProcessingAi = true;
    _fullGeminiResponse = "";
    activeActionStatus = "Identifying items in scene...";
    onStateChanged();

    final totalStopwatch = Stopwatch()..start();

    try {
      Vibration.vibrate(duration: 80);
      await ttsService.speak("Scanning scene.");

      final captureStart = totalStopwatch.elapsedMilliseconds;
      final rawBytes = await cameraService.captureImage();
      final captureComplete = totalStopwatch.elapsedMilliseconds;

      if (rawBytes == null || rawBytes.isEmpty) {
        _fullGeminiResponse = "Captured image is empty.";
        activeActionStatus = "Captured image is empty.";
        await ttsService.speak(_fullGeminiResponse);
        return;
      }

      // Step 1: Fast Image Compression and Optimization (4MB -> ~100KB)
      final imageBytes = await ImageCompressor.compressForVision(rawBytes);
      final prepComplete = totalStopwatch.elapsedMilliseconds;

      if (imageBytes.isEmpty) {
        _fullGeminiResponse = "Captured image is empty.";
        activeActionStatus = "Captured image is empty.";
        await ttsService.speak(_fullGeminiResponse);
        return;
      }

      // Step 2: Request Scene Understanding from Gemini Vision
      final aiStart = totalStopwatch.elapsedMilliseconds;
      final description = await geminiService.describeScene(imageBytes);
      final aiComplete = totalStopwatch.elapsedMilliseconds;

      _fullGeminiResponse = description;
      activeActionStatus = "Scan complete. Reading result...";
      onStateChanged();

      debugPrint("GEMINI RESPONSE LENGTH: ${_fullGeminiResponse.length}");

      Vibration.vibrate(duration: 80);
      final ttsStart = totalStopwatch.elapsedMilliseconds;
      await ttsService.speak(_fullGeminiResponse);

      // Latency Logging
      debugPrint("[PERF] Item Scanner capture: ${captureComplete - captureStart}ms");
      debugPrint("[PERF] Image optimization: ${prepComplete - captureComplete}ms (size: ${(imageBytes.length / 1024).toStringAsFixed(1)}KB)");
      debugPrint("[PERF] Gemini response: ${aiComplete - aiStart}ms");
      debugPrint("[PERF] TTS start: ${ttsStart - aiComplete}ms");
      debugPrint("[PERF] Total scan-to-speech latency: ${totalStopwatch.elapsedMilliseconds}ms");
    } catch (e) {
      _fullGeminiResponse = "";
      final userMessage = (e is GeminiException)
          ? e.userMessage
          : "Gemini service is temporarily unavailable.";
      activeActionStatus = userMessage;
      await ttsService.speak(userMessage);
    } finally {
      isProcessingAi = false;
      _isAiRequestInProgress = false;
      onStateChanged();
      evaluateStreamRequirement(onStateChanged: onStateChanged);
    }
  }

  /// Document Reader: Capture & read document with OCR priority
  Future<void> scanDocument({required VoidCallback onStateChanged}) async {
    if (_isAiRequestInProgress || !cameraService.isInitialized) return;

    await cameraService.stopStream();

    _isAiRequestInProgress = true;
    isProcessingAi = true;
    _fullGeminiResponse = "";
    activeActionStatus = "Reading entire document...";
    onStateChanged();

    try {
      Vibration.vibrate(duration: 80);
      await ttsService.speak("Reading document.");

      final rawBytes = await cameraService.captureImage();
      if (rawBytes == null || rawBytes.isEmpty) {
        _fullGeminiResponse = "Captured image is empty.";
        activeActionStatus = "Captured image is empty.";
        await ttsService.speak(_fullGeminiResponse);
        return;
      }

      final imageBytes = await ImageCompressor.compressForVision(
        rawBytes,
        maxDimension: 1280, // High quality for document OCR
        quality: 88,
      );

      final resultText = await geminiService.readDocument(imageBytes);

      _fullGeminiResponse = resultText;
      activeActionStatus = "Reading document text...";
      onStateChanged();

      debugPrint("GEMINI RESPONSE LENGTH: ${_fullGeminiResponse.length}");

      Vibration.vibrate(duration: 80);
      await ttsService.speak(_fullGeminiResponse);
    } catch (e) {
      _fullGeminiResponse = "";
      final userMessage = (e is GeminiException)
          ? e.userMessage
          : "Gemini service is temporarily unavailable.";
      activeActionStatus = userMessage;
      await ttsService.speak(userMessage);
    } finally {
      isProcessingAi = false;
      _isAiRequestInProgress = false;
      onStateChanged();
      evaluateStreamRequirement(onStateChanged: onStateChanged);
    }
  }

  /// Voice Follow-up: Start speech recognition
  Future<void> startVoiceQuestionCapture({required VoidCallback onStateChanged}) async {
    if (isProcessingAi || isListeningSpeech) return;

    await ttsService.stop();
    Vibration.vibrate(duration: 150);

    isListeningSpeech = true;
    activeActionStatus = "🎤 Listening... (Speak your question)";
    onStateChanged();

    await speechService.startListening(
      onResult: (words) {
        activeActionStatus = "🎤 \"$words\"";
        onStateChanged();
      },
      onFinalized: () {
        finalizeVoiceQuestion(onStateChanged: onStateChanged);
      },
    );
  }

  void finalizeVoiceQuestion({required VoidCallback onStateChanged}) {
    if (!isListeningSpeech) return;

    isListeningSpeech = false;
    final capturedText = speechService.lastRecognizedWords.trim();
    speechService.stop();

    if (capturedText.isNotEmpty) {
      processFollowUp(capturedText, onStateChanged: onStateChanged);
    } else {
      activeActionStatus = "Sight: $currentToolName";
      onStateChanged();
      ttsService.speak("No question heard.");
    }
  }

  void cancelVoiceQuestion({required VoidCallback onStateChanged}) {
    if (isListeningSpeech) {
      isListeningSpeech = false;
      activeActionStatus = "Sight: $currentToolName";
      speechService.cancel();
      onStateChanged();
    }
  }

  /// Process Voice Follow-Up: Single Gemini Multimodal Request using stored image
  Future<void> processFollowUp(
    String question, {
    required VoidCallback onStateChanged,
  }) async {
    if (_isAiRequestInProgress) return;

    _isAiRequestInProgress = true;
    isProcessingAi = true;
    activeActionStatus = "Analyzing question...";
    onStateChanged();

    final stopwatch = Stopwatch()..start();

    try {
      if (!geminiService.hasStoredImage) {
        _fullGeminiResponse = "No image scanned yet. Please scan a scene first.";
        activeActionStatus = _fullGeminiResponse;
        onStateChanged();
        await ttsService.speak(_fullGeminiResponse);
        return;
      }

      // Local intent classification (0ms)
      final localIntent = _classifyIntentLocally(question);

      activeActionStatus = "AI: Answering question...";
      onStateChanged();

      final aiStart = stopwatch.elapsedMilliseconds;
      final answer = await geminiService.answerFollowUp(
        followUpQuestion: question,
        intentLabel: localIntent.label,
      );
      final aiComplete = stopwatch.elapsedMilliseconds;

      _fullGeminiResponse = answer;
      activeActionStatus = "Reading answer...";
      onStateChanged();

      debugPrint("GEMINI RESPONSE LENGTH: ${_fullGeminiResponse.length}");

      Vibration.vibrate(duration: 80);
      final ttsStart = stopwatch.elapsedMilliseconds;
      await ttsService.speak(_fullGeminiResponse);

      debugPrint("[PERF] Follow-up Gemini response: ${aiComplete - aiStart}ms");
      debugPrint("[PERF] Follow-up TTS start: ${ttsStart - aiComplete}ms");
      debugPrint("[PERF] Total follow-up latency: ${stopwatch.elapsedMilliseconds}ms");
    } catch (e) {
      _fullGeminiResponse = "";
      final userMessage = (e is GeminiException)
          ? e.userMessage
          : "Gemini service is temporarily unavailable.";
      activeActionStatus = userMessage;
      await ttsService.speak(userMessage);
    } finally {
      isProcessingAi = false;
      _isAiRequestInProgress = false;
      onStateChanged();
      evaluateStreamRequirement(onStateChanged: onStateChanged);
    }
  }

  AiIntent _classifyIntentLocally(String question) {
    final lower = question.toLowerCase().trim();
    if (lower.contains("color") || lower.contains("shade") || lower.contains("colour")) {
      return AiIntent.color;
    }
    if (lower.contains("how many") || lower.contains("count") || lower.contains("number of")) {
      return AiIntent.quantity;
    }
    if (lower.contains("written") || lower.contains("text") || lower.contains("read") || lower.contains("word") || lower.contains("say")) {
      return AiIntent.textContent;
    }
    if (lower.contains("where") || lower.contains("position") || lower.contains("location") || lower.contains("next to") || lower.contains("beside") || lower.contains("near")) {
      return AiIntent.location;
    }
    if (lower.contains("price") || lower.contains("cost") || lower.contains("how much") || lower.contains("dollar") || lower.contains("rupee")) {
      return AiIntent.price;
    }
    if (lower.contains("brand") || lower.contains("company") || lower.contains("make") || lower.contains("manufacturer")) {
      return AiIntent.brand;
    }
    if (lower.contains("state") || lower.contains("full") || lower.contains("empty") || lower.contains("open") || lower.contains("closed")) {
      return AiIntent.objectState;
    }
    if (lower.contains("person") || lower.contains("people") || lower.contains("someone") || lower.contains("who")) {
      return AiIntent.personPresence;
    }
    if (lower.contains("what is") || lower.contains("what are") || lower.contains("identify") || lower.contains("this")) {
      return AiIntent.objectIdentification;
    }
    return AiIntent.generalQuestion;
  }

  /// Toggle Flashlight (uses CameraController natively when active to fix Torch Light!)
  Future<void> toggleTorch({required VoidCallback onStateChanged}) async {
    try {
      final isOn = await torchService.toggleTorch(cameraService.controller);
      activeActionStatus = isOn ? "Torch: Active" : "Torch: Off";
      Vibration.vibrate(duration: 50);
      await ttsService.speak(isOn ? "Torch on" : "Torch off");
    } catch (e) {
      activeActionStatus = "Torch: Hardware unavailable";
      await ttsService.speak("Flashlight is not available on this device.");
    }
    onStateChanged();
  }

  /// Live document detection stream
  void evaluateStreamRequirement({required VoidCallback onStateChanged}) {
    if (isLocked && _sightToolIndex == 1) {
      _startLiveStreamGuidance(onStateChanged: onStateChanged);
    } else {
      cameraService.stopStream();
    }
  }

  Future<void> _startLiveStreamGuidance({
    required VoidCallback onStateChanged,
  }) async {
    if (!cameraService.isInitialized || cameraService.isStreamRunning) return;

    try {
      _documentStabilityScore = 0;
      await cameraService.startStream((CameraImage image) {
        if (_isAnalyzingStream || isProcessingAi || !isLocked || _sightToolIndex != 1) {
          return;
        }

        _isAnalyzingStream = true;
        try {
          final plane = image.planes.first;
          final bytes = plane.bytes;

          final int start = (bytes.length * 0.25).toInt();
          final int end = (bytes.length * 0.75).toInt();
          const int step = 4;

          int edgeContrastCount = 0;
          int samplePoints = 0;

          for (int i = start; i < end - step; i += step * 3) {
            final int diff = (bytes[i] - bytes[i + step]).abs();
            if (diff > 35) {
              edgeContrastCount++;
            }
            samplePoints++;
          }

          final double edgeDensity =
              samplePoints > 0 ? (edgeContrastCount / samplePoints) : 0.0;

          if (edgeDensity > 0.08) {
            _documentStabilityScore++;
          } else {
            _documentStabilityScore = (_documentStabilityScore - 1).clamp(0, 10);
          }

          final now = DateTime.now();
          if (_documentStabilityScore >= 3 &&
              now.difference(_lastGuidanceNotification).inMilliseconds > 2000) {
            _lastGuidanceNotification = now;

            Vibration.vibrate(duration: 90);
            ttsService.speak("Document detected. Hold still to read.");

            activeActionStatus = "Document in view (Click Vol Down)";
            onStateChanged();
          }
        } catch (e) {
          debugPrint("Stream analysis error: $e");
        } finally {
          _isAnalyzingStream = false;
        }
      });
    } catch (e) {
      debugPrint("Failed to start document guidance stream: $e");
    }
  }
}
