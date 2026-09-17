import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../constants/gemini_prompts.dart';
import '../models/ai_intent.dart';
import '../models/conversation_turn.dart';

class GeminiException implements Exception {
  final String userMessage;
  final int? statusCode;
  final String? responseBody;

  GeminiException(
    this.userMessage, {
    this.statusCode,
    this.responseBody,
  });

  @override
  String toString() => userMessage;
}

class GeminiQuotaException extends GeminiException {
  GeminiQuotaException([
    super.userMessage = "Gemini request limit reached (429). Please try again later.",
    int? statusCode = 429,
    String? responseBody,
  ]) : super(
          statusCode: statusCode,
          responseBody: responseBody,
        );
}

class GeminiService {
  static const String geminiModel = "gemini-3.6-flash";
  static const String _defaultApiKey = String.fromEnvironment(
    'GEMINI_API_KEY',
    defaultValue: 'YOUR_GEMINI_API_KEY_HERE',
  );
  final String _apiKey;

  Uint8List? _lastScannedImageBytes;
  final List<ConversationTurn> _conversationTurns = [];

  GeminiService({String? apiKey}) : _apiKey = apiKey ?? _defaultApiKey;

  Uint8List? get lastScannedImageBytes => _lastScannedImageBytes;
  bool get hasStoredImage => _lastScannedImageBytes != null && _lastScannedImageBytes!.isNotEmpty;

  String get _cleanApiKey => _apiKey.trim();

  Uri _getEndpointUri() {
    final key = _cleanApiKey;
    return Uri.parse(
      "https://generativelanguage.googleapis.com/v1beta/models/$geminiModel:generateContent?key=$key",
    );
  }

  void clearConversation() {
    _conversationTurns.clear();
    _lastScannedImageBytes = null;
  }

  void _logKeyDiagnostic() {
    final key = _cleanApiKey;
    final suffix = key.length >= 4 ? key.substring(key.length - 4) : "N/A";
    debugPrint("GEMINI KEY DIAGNOSTIC: loaded=${key.isNotEmpty}, length=${key.length}, suffix=...$suffix");
  }

  /// Step 1 & 2: Describe scene (Item Scanner)
  Future<String> describeScene(Uint8List imageBytes) async {
    if (imageBytes.isEmpty) {
      debugPrint("Gemini request failed: Captured image is empty.");
      throw GeminiException("Captured image is empty.");
    }

    _logKeyDiagnostic();
    debugPrint("GEMINI REQUEST START");
    _lastScannedImageBytes = imageBytes;
    _conversationTurns.clear();

    final base64Image = base64Encode(imageBytes);
    if (base64Image.isEmpty) {
      debugPrint("Gemini request failed: Base64 image encoding resulted in empty string.");
      throw GeminiException("Captured image is empty.");
    }

    final initialTurn = ConversationTurn.imageUser(
      textPrompt: GeminiPrompts.sceneDescriptionPrompt,
      base64Image: base64Image,
    );

    _conversationTurns.add(initialTurn);

    final responseText = await _sendToGemini(
      maxTokens: 300,
      temperature: 0.2,
    );

    _conversationTurns.add(ConversationTurn.modelText(responseText));

    return _cleanTextForTts(responseText);
  }

  /// Document Reader: Read entire document text
  Future<String> readDocument(Uint8List imageBytes) async {
    if (imageBytes.isEmpty) {
      debugPrint("Gemini request failed: Captured image is empty.");
      throw GeminiException("Captured image is empty.");
    }

    _logKeyDiagnostic();
    debugPrint("GEMINI REQUEST START");
    _lastScannedImageBytes = imageBytes;
    _conversationTurns.clear();

    final base64Image = base64Encode(imageBytes);
    if (base64Image.isEmpty) {
      debugPrint("Gemini request failed: Base64 image encoding resulted in empty string.");
      throw GeminiException("Captured image is empty.");
    }

    final initialTurn = ConversationTurn.imageUser(
      textPrompt: GeminiPrompts.documentReaderPrompt,
      base64Image: base64Image,
    );

    _conversationTurns.add(initialTurn);

    final responseText = await _sendToGemini(
      maxTokens: 500,
      temperature: 0.1,
    );

    _conversationTurns.add(ConversationTurn.modelText(responseText));

    return _cleanTextForTts(responseText);
  }

  /// Step 4: Extract intent from spoken follow-up question
  Future<AiIntent> extractIntent(String followUpQuestion) async {
    final key = _cleanApiKey;
    if (key.isEmpty || key == "YOUR_GEMINI_API_KEY_HERE") {
      return AiIntent.generalQuestion;
    }

    final prompt = "${GeminiPrompts.intentExtractionPrompt}\n$followUpQuestion";
    final body = jsonEncode({
      "contents": [
        ConversationTurn.textUser(prompt).toJson()
      ],
      "generationConfig": {
        "maxOutputTokens": 30,
        "temperature": 0.0,
      }
    });

    try {
      final response = await _postWithRetry(
        _getEndpointUri(),
        {"Content-Type": "application/json"},
        body,
      );

      final rawText = _extractTextFromResponse(response);
      return AiIntent.parse(rawText);
    } catch (e) {
      debugPrint("Intent extraction error: $e");
      if (e is GeminiException) {
        rethrow;
      }
    }

    return AiIntent.generalQuestion;
  }

  /// Step 5: Answer follow-up question using original image and intent
  Future<String> answerFollowUp({
    required String followUpQuestion,
    required String intentLabel,
  }) async {
    if (_lastScannedImageBytes == null || _lastScannedImageBytes!.isEmpty) {
      return "No image scanned yet. Please scan a scene first.";
    }

    _logKeyDiagnostic();
    debugPrint("GEMINI REQUEST START");
    final prompt = GeminiPrompts.followUpQuestionPrompt(
      question: followUpQuestion,
      intent: intentLabel,
    );

    _conversationTurns.add(ConversationTurn.textUser(prompt));

    final responseText = await _sendToGemini(
      maxTokens: 300,
      temperature: 0.2,
    );

    _conversationTurns.add(ConversationTurn.modelText(responseText));

    return _cleanTextForTts(responseText);
  }

  Future<String> _sendToGemini({
    int maxTokens = 300,
    double temperature = 0.2,
  }) async {
    final key = _cleanApiKey;
    if (key.isEmpty || key == "YOUR_GEMINI_API_KEY_HERE") {
      throw GeminiException("Gemini authentication failed. Please check the API configuration.");
    }

    final body = jsonEncode({
      "contents": _conversationTurns.map((t) => t.toJson()).toList(),
      "generationConfig": {
        "maxOutputTokens": maxTokens,
        "temperature": temperature,
      }
    });

    final response = await _postWithRetry(
      _getEndpointUri(),
      {"Content-Type": "application/json"},
      body,
    );

    return _extractTextFromResponse(response);
  }

  Future<http.Response> _postWithRetry(
    Uri baseUri,
    Map<String, String> headers,
    String body,
  ) async {
    const int maxRetries = 5;
    final Random random = Random();

    for (int attempt = 1; attempt <= maxRetries + 1; attempt++) {
      try {
        debugPrint("Gemini request attempt: $attempt");

        final response = await http.post(baseUri, headers: headers, body: body);

        final statusCode = response.statusCode;
        final responseBody = response.body;

        debugPrint("GEMINI RESPONSE RECEIVED");
        debugPrint("GEMINI HTTP STATUS: $statusCode");
        debugPrint("GEMINI RESPONSE: $responseBody");

        if (statusCode == 200) {
          return response;
        }

        // Non-retryable HTTP status codes
        if (statusCode == 400) {
          String userMsg = "Gemini request is invalid.";
          try {
            final decoded = jsonDecode(responseBody);
            final errorMap = decoded['error'];
            if (errorMap is Map) {
              final msg = errorMap['message']?.toString() ?? "";
              if (msg.contains("API key not valid") || msg.contains("API_KEY_INVALID")) {
                userMsg = "Gemini authentication failed. Please check the API configuration.";
              }
            }
          } catch (_) {}

          throw GeminiException(
            userMsg,
            statusCode: statusCode,
            responseBody: responseBody,
          );
        } else if (statusCode == 401) {
          throw GeminiException(
            "Gemini authentication failed. Please check the API configuration.",
            statusCode: statusCode,
            responseBody: responseBody,
          );
        } else if (statusCode == 403) {
          throw GeminiException(
            "Gemini access is not permitted.",
            statusCode: statusCode,
            responseBody: responseBody,
          );
        } else if (statusCode == 404) {
          throw GeminiException(
            "Gemini model is unavailable.",
            statusCode: statusCode,
            responseBody: responseBody,
          );
        }

        // Retryable HTTP status codes: 429, 408, 500, 502, 503, 504
        if (statusCode == 429 ||
            statusCode == 408 ||
            statusCode == 500 ||
            statusCode == 502 ||
            statusCode == 503 ||
            statusCode == 504) {
          if (attempt > maxRetries) {
            final userMsg = statusCode == 429
                ? "Gemini request limit reached. Please try again later."
                : "Gemini service is temporarily unavailable.";
            throw GeminiException(
              userMsg,
              statusCode: statusCode,
              responseBody: responseBody,
            );
          }
        } else {
          if (attempt > maxRetries) {
            throw GeminiException(
              "Gemini service is temporarily unavailable.",
              statusCode: statusCode,
              responseBody: responseBody,
            );
          }
        }

        int delaySec = pow(2, attempt - 1).toInt();
        if (delaySec > 16) delaySec = 16;

        final retryAfterHeader = response.headers['retry-after'];
        if (retryAfterHeader != null) {
          final parsedSec = int.tryParse(retryAfterHeader);
          if (parsedSec != null && parsedSec > 0 && parsedSec <= 15) {
            delaySec = max(delaySec, parsedSec);
          }
        }

        final jitterMs = random.nextInt(300);
        final totalDelayMs = (delaySec * 1000) + jitterMs;

        debugPrint(
          "Gemini attempt $attempt failed with HTTP $statusCode. Waiting ${totalDelayMs}ms before next attempt...",
        );
        await Future.delayed(Duration(milliseconds: totalDelayMs));
      } on SocketException catch (e) {
        debugPrint("Gemini network exception on attempt $attempt: $e");
        if (attempt > maxRetries) {
          throw GeminiException("Network connection unavailable.");
        }
        final delaySec = pow(2, attempt - 1).toInt().clamp(1, 16);
        final totalDelayMs = (delaySec * 1000) + random.nextInt(300);
        await Future.delayed(Duration(milliseconds: totalDelayMs));
      } on TimeoutException catch (e) {
        debugPrint("Gemini timeout exception on attempt $attempt: $e");
        if (attempt > maxRetries) {
          throw GeminiException("Network connection unavailable.");
        }
        final delaySec = pow(2, attempt - 1).toInt().clamp(1, 16);
        final totalDelayMs = (delaySec * 1000) + random.nextInt(300);
        await Future.delayed(Duration(milliseconds: totalDelayMs));
      } catch (e) {
        if (e is GeminiException) rethrow;
        debugPrint("Gemini exception on attempt $attempt: $e");
        if (attempt > maxRetries) {
          throw GeminiException("Gemini service is temporarily unavailable.");
        }
        final delaySec = pow(2, attempt - 1).toInt().clamp(1, 16);
        final totalDelayMs = (delaySec * 1000) + random.nextInt(300);
        await Future.delayed(Duration(milliseconds: totalDelayMs));
      }
    }

    throw GeminiException("Gemini service is temporarily unavailable.");
  }

  String _extractTextFromResponse(http.Response response) {
    if (response.body.trim().isEmpty) {
      debugPrint("Gemini response body was empty.");
      throw GeminiException("Gemini returned an empty response.");
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (e) {
      debugPrint("Failed to parse Gemini JSON response: $e");
      throw GeminiException("Gemini request is invalid.");
    }

    if (decoded is! Map<String, dynamic>) {
      debugPrint("Gemini response is not a Map: ${response.body}");
      throw GeminiException("Gemini request is invalid.");
    }

    if (decoded.containsKey('error')) {
      final errorMap = decoded['error'];
      final code = errorMap is Map ? errorMap['code'] : null;
      final message = errorMap is Map ? errorMap['message'] : null;
      final statusStr = errorMap is Map ? errorMap['status'] : null;
      debugPrint("Gemini response contained error object: $code ($statusStr) - $message");

      if (code == 400 || statusStr == "INVALID_ARGUMENT") {
        if (message != null && message.toString().contains("API key not valid")) {
          throw GeminiException("Gemini authentication failed. Please check the API configuration.");
        }
        throw GeminiException("Gemini request is invalid.");
      } else if (code == 401) {
        throw GeminiException("Gemini authentication failed. Please check the API configuration.");
      } else if (code == 403) {
        throw GeminiException("Gemini access is not permitted.");
      } else if (code == 404) {
        throw GeminiException("Gemini model is unavailable.");
      } else if (code == 429) {
        throw GeminiException("Gemini request limit reached. Please try again later.");
      }
      throw GeminiException("Gemini service is temporarily unavailable.");
    }

    final candidates = decoded['candidates'];
    if (candidates is! List || candidates.isEmpty) {
      debugPrint("Gemini response candidates field missing or empty.");
      throw GeminiException("Gemini returned an empty response.");
    }

    final firstCandidate = candidates.first;
    if (firstCandidate is! Map<String, dynamic>) {
      debugPrint("Gemini candidate is not a Map.");
      throw GeminiException("Gemini returned an empty response.");
    }

    final content = firstCandidate['content'];
    if (content is! Map<String, dynamic>) {
      debugPrint("Gemini candidate content missing or invalid.");
      throw GeminiException("Gemini returned an empty response.");
    }

    final parts = content['parts'];
    if (parts is! List || parts.isEmpty) {
      debugPrint("Gemini content parts missing or empty.");
      throw GeminiException("Gemini returned an empty response.");
    }

    final firstPart = parts.first;
    if (firstPart is! Map<String, dynamic>) {
      debugPrint("Gemini part is not a Map.");
      throw GeminiException("Gemini returned an empty response.");
    }

    final text = firstPart['text'];
    if (text == null || text.toString().trim().isEmpty) {
      debugPrint("Gemini part text is null or empty.");
      throw GeminiException("Gemini returned an empty response.");
    }

    return text.toString().trim();
  }

  String _cleanTextForTts(String text) {
    return text
        .replaceAll(RegExp(r'[*#_`]'), '')
        .replaceAll(RegExp(r'^\s*[-*]\s+', multiLine: true), '')
        .replaceAll(RegExp(r'\n+'), ' ')
        .trim();
  }
}
