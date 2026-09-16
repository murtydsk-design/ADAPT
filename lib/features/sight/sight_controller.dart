import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:vibration/vibration.dart';
import '../../core/services/camera_service.dart';
import '../../core/services/gemini_service.dart';
import '../../core/services/ml_kit_service.dart';
import '../../core/services/speech_service.dart';
import '../../core/services/torch_service.dart';
import '../../core/services/tts_service.dart';

class SightController {
  final CameraService cameraService;
  final GeminiService geminiService;
  final MlKitService mlKitService;
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

  // Request lock to prevent duplicate concurrent Gemini calls
  bool _isAiRequestInProgress = false;

  MlKitAnalysisResult? _lastMlKitResult;
  MlKitAnalysisResult? get lastMlKitResult => _lastMlKitResult;

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
    required this.mlKitService,
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
    _lastMlKitResult = null;
    await torchService.turnOff();
    await cameraService.disposeCamera();
    onStateChanged();
  }

  void cycleSightTool({required VoidCallback onStateChanged}) {
    if (isProcessingAi || isListeningSpeech) return;

    _fullGeminiResponse = "";
    geminiService.clearConversation();
    _lastMlKitResult = null;
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

  /// Item Scanner: Capture 1 image, run ML Kit on-device processing + Gemini
  Future<void> scanScene({required VoidCallback onStateChanged}) async {
    if (_isAiRequestInProgress || !cameraService.isInitialized) return;

    await cameraService.stopStream();

    _isAiRequestInProgress = true;
    isProcessingAi = true;
    _fullGeminiResponse = "";
    activeActionStatus = "Identifying items in scene...";
    onStateChanged();

    try {
      Vibration.vibrate(duration: 80);
      await ttsService.speak("Scanning scene.");

      final imageBytes = await cameraService.captureImage();
      if (imageBytes == null) {
        _fullGeminiResponse = "Failed to capture image.";
        activeActionStatus = "Failed to capture image.";
        await ttsService.speak(_fullGeminiResponse);
        return;
      }

      // Step 1: Run On-Device ML Kit Processing for supporting context
      _lastMlKitResult = await mlKitService.analyzeImage(imageBytes);
      final mlKitContext = _lastMlKitResult?.toContextPrompt();

      // Step 2: Request Deep Scene Understanding from Gemini 3.6 Flash
      final description = await geminiService.describeScene(
        imageBytes,
        mlKitContext: mlKitContext,
      );

      _fullGeminiResponse = description;
      activeActionStatus = description.length > 300
          ? "${description.substring(0, 300)}..."
          : description;
      onStateChanged();

      Vibration.vibrate(duration: 80);
      await ttsService.speak(_fullGeminiResponse);
    } catch (e) {
      _fullGeminiResponse = "";
      final userMessage = (e is GeminiException)
          ? e.userMessage
          : "Gemini is temporarily busy. Please try again.";
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

      final imageBytes = await cameraService.captureImage();
      if (imageBytes == null) {
        _fullGeminiResponse = "Failed to capture document.";
        activeActionStatus = "Failed to capture document.";
        await ttsService.speak(_fullGeminiResponse);
        return;
      }

      final resultText = await geminiService.readDocument(imageBytes);

      _fullGeminiResponse = resultText;
      activeActionStatus = resultText.length > 300
          ? "${resultText.substring(0, 300)}..."
          : resultText;
      onStateChanged();

      Vibration.vibrate(duration: 80);
      await ttsService.speak(_fullGeminiResponse);
    } catch (e) {
      _fullGeminiResponse = "";
      final userMessage = (e is GeminiException)
          ? e.userMessage
          : "Gemini is temporarily busy. Please try again.";
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

  /// Process Voice Follow-Up: Decision Engine (ML Kit Simple vs Gemini Complex)
  Future<void> processFollowUp(
    String question, {
    required VoidCallback onStateChanged,
  }) async {
    if (_isAiRequestInProgress) return;

    _isAiRequestInProgress = true;
    isProcessingAi = true;
    activeActionStatus = "Analyzing question...";
    onStateChanged();

    try {
      // Step 1: Check if simple question can be reliably answered on-device via ML Kit
      final onDeviceAnswer = _tryAnswerOnDevice(question, _lastMlKitResult);
      if (onDeviceAnswer != null) {
        _fullGeminiResponse = onDeviceAnswer;
        activeActionStatus = onDeviceAnswer;
        onStateChanged();

        Vibration.vibrate(duration: 80);
        await ttsService.speak(_fullGeminiResponse);
        return;
      }

      // Step 2: Complex visual task -> Intent Extraction + Gemini 3.6 Flash
      final intent = await geminiService.extractIntent(question);

      activeActionStatus = "AI: Answering question...";
      onStateChanged();

      final mlKitContext = _lastMlKitResult?.toContextPrompt();
      final answer = await geminiService.answerFollowUp(
        followUpQuestion: question,
        intentLabel: intent.label,
        mlKitContext: mlKitContext,
      );

      _fullGeminiResponse = answer;
      activeActionStatus = answer.length > 300
          ? "${answer.substring(0, 300)}..."
          : answer;
      onStateChanged();

      Vibration.vibrate(duration: 80);
      await ttsService.speak(_fullGeminiResponse);
    } catch (e) {
      _fullGeminiResponse = "";
      final userMessage = (e is GeminiException)
          ? e.userMessage
          : "Gemini is temporarily busy. Please try again.";
      activeActionStatus = userMessage;
      await ttsService.speak(userMessage);
    } finally {
      isProcessingAi = false;
      _isAiRequestInProgress = false;
      onStateChanged();
      evaluateStreamRequirement(onStateChanged: onStateChanged);
    }
  }

  String? _tryAnswerOnDevice(String question, MlKitAnalysisResult? mlKit) {
    if (mlKit == null) return null;

    final lower = question.toLowerCase().trim();

    // 1. Text reading requests
    if (lower.contains("read text") ||
        lower.contains("read the text") ||
        lower.contains("what does it say") ||
        lower.contains("what text is")) {
      if (mlKit.hasText && mlKit.fullText.length > 2) {
        return "The text reads: ${mlKit.fullText}";
      } else {
        return "No text was detected in the image.";
      }
    }

    final reliableObjectCategories = {
      "laptop", "bottle", "person", "book", "chair", "car", "phone",
      "mobile phone", "keyboard", "mouse", "cup", "bag",
      "cat", "dog", "plant", "monitor", "tv", "desk", "table"
    };

    // 2. Simple object presence checks (e.g. "is there a laptop", "do you see a bottle")
    final presenceRegex = RegExp(
      r'\b(?:is|are)\s+there\s+(?:a|an|any)?\s*([a-z\s]+)\b|\bdo\s+you\s+see\s+(?:a|an|any)?\s*([a-z\s]+)\b',
    );
    final match = presenceRegex.firstMatch(lower);
    if (match != null) {
      final target = (match.group(1) ?? match.group(2) ?? "").trim();
      if (target.isNotEmpty && target.length > 2) {
        final isReliableTarget = reliableObjectCategories.any((cat) => target.contains(cat) || cat.contains(target));
        if (isReliableTarget) {
          final specificObjects = mlKit.objectNames.map((e) => e.toLowerCase()).toList();
          final isPresent = specificObjects.any((item) => item.contains(target) || target.contains(item));
          if (isPresent) {
            return "Yes, $target is detected.";
          } else {
            return "No $target was detected in the on-device scan.";
          }
        }
      }
    }

    return null;
  }

  /// Toggle Flashlight
  Future<void> toggleTorch({required VoidCallback onStateChanged}) async {
    try {
      final isOn = await torchService.toggleTorch();
      activeActionStatus = isOn ? "Torch: Active" : "Torch: Off";
      Vibration.vibrate(duration: 50);
      await ttsService.speak(isOn ? "Torch on" : "Torch off");
    } catch (e) {
      await ttsService.speak("Torch hardware failed");
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
