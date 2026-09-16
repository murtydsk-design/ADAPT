import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class MlKitAnalysisResult {
  final List<DetectedObject> detectedObjects;
  final List<ImageLabel> labels;
  final RecognizedText recognizedText;

  MlKitAnalysisResult({
    required this.detectedObjects,
    required this.labels,
    required this.recognizedText,
  });

  List<String> get objectNames {
    final names = <String>{};
    for (final obj in detectedObjects) {
      for (final label in obj.labels) {
        if (label.confidence > 0.45) {
          names.add(label.text);
        }
      }
    }
    return names.toList();
  }

  List<String> get labelNames {
    return labels
        .where((l) => l.confidence > 0.5)
        .map((l) => l.label)
        .toList();
  }

  String get fullText => recognizedText.text.trim();
  bool get hasText => fullText.isNotEmpty;

  String toContextPrompt() {
    final buf = StringBuffer();
    buf.writeln("On-device ML Kit Detections:");

    final objs = objectNames;
    if (objs.isNotEmpty) {
      buf.writeln("- Detected Objects: ${objs.join(', ')}");
    }

    final lbls = labelNames;
    if (lbls.isNotEmpty) {
      buf.writeln("- Image Labels: ${lbls.join(', ')}");
    }

    if (hasText) {
      final sampleText = fullText.length > 200
          ? "${fullText.substring(0, 200)}..."
          : fullText;
      buf.writeln("- Recognized Text Snippet: \"$sampleText\"");
    }

    return buf.toString().trim();
  }
}

class MlKitService {
  late final ObjectDetector _objectDetector;
  late final ImageLabeler _imageLabeler;
  late final TextRecognizer _textRecognizer;
  bool _isInitialized = false;

  void _ensureInitialized() {
    if (_isInitialized) return;

    final objectOptions = ObjectDetectorOptions(
      mode: DetectionMode.single,
      classifyObjects: true,
      multipleObjects: true,
    );
    _objectDetector = ObjectDetector(options: objectOptions);

    final labelerOptions = ImageLabelerOptions(confidenceThreshold: 0.45);
    _imageLabeler = ImageLabeler(options: labelerOptions);

    _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

    _isInitialized = true;
  }

  Future<MlKitAnalysisResult?> analyzeImage(Uint8List imageBytes) async {
    try {
      _ensureInitialized();

      final tempDir = Directory.systemTemp;
      final tempFile = File(
        '${tempDir.path}/mlkit_temp_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await tempFile.writeAsBytes(imageBytes);

      final inputImage = InputImage.fromFilePath(tempFile.path);

      final detectedObjects = await _objectDetector.processImage(inputImage);
      final labels = await _imageLabeler.processImage(inputImage);
      final recognizedText = await _textRecognizer.processImage(inputImage);

      try {
        await tempFile.delete();
      } catch (_) {}

      return MlKitAnalysisResult(
        detectedObjects: detectedObjects,
        labels: labels,
        recognizedText: recognizedText,
      );
    } catch (e) {
      debugPrint("ML Kit processing exception: $e");
      return null;
    }
  }

  void dispose() {
    if (_isInitialized) {
      _objectDetector.close();
      _imageLabeler.close();
      _textRecognizer.close();
      _isInitialized = false;
    }
  }
}
