import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../constants/openai_prompts.dart';

class OpenAiException implements Exception {
  final String userMessage;
  final int? statusCode;
  final String? responseBody;

  OpenAiException(
    this.userMessage, {
    this.statusCode,
    this.responseBody,
  });

  @override
  String toString() => userMessage;
}

class OpenAiService {
  static const String openAiModel = "gpt-4o-mini";
  static const String _defaultApiKey = String.fromEnvironment(
    'OPENAI_API_KEY',
    defaultValue: 'YOUR_OPENAI_API_KEY_HERE',
  );
  final String _apiKey;

  Uint8List? _lastScannedImageBytes;

  OpenAiService({String? apiKey}) : _apiKey = apiKey ?? _defaultApiKey;

  Uint8List? get lastScannedImageBytes => _lastScannedImageBytes;
  bool get hasStoredImage => _lastScannedImageBytes != null && _lastScannedImageBytes!.isNotEmpty;

  String get _cleanApiKey => _apiKey.trim();

  void clearConversation() {
    _lastScannedImageBytes = null;
  }

  void _logKeyDiagnostic() {
    final key = _cleanApiKey;
    final suffix = key.length >= 4 ? key.substring(key.length - 4) : "N/A";
    debugPrint("OPENAI KEY DIAGNOSTIC: loaded=${key.isNotEmpty}, length=${key.length}, suffix=...$suffix");
  }

  /// Initial Item Scanner Scene Description
  Future<String> describeScene(Uint8List imageBytes) async {
    if (imageBytes.isEmpty) {
      debugPrint("OpenAI request failed: Captured image is empty.");
      throw OpenAiException("Captured image is empty.");
    }

    _logKeyDiagnostic();
    debugPrint("OPENAI REQUEST START");
    _lastScannedImageBytes = imageBytes;

    final base64Image = base64Encode(imageBytes);
    if (base64Image.isEmpty) {
      debugPrint("OpenAI request failed: Base64 image encoding resulted in empty string.");
      throw OpenAiException("Captured image is empty.");
    }
    debugPrint("OPENAI Image preparation completed");

    final responseText = await _sendVisionRequest(
      prompt: OpenAiPrompts.sceneDescriptionPrompt,
      base64Image: base64Image,
      maxTokens: 300,
    );

    return _cleanTextForTts(responseText);
  }

  /// Document Reader: Full OCR transcription
  Future<String> readDocument(Uint8List imageBytes) async {
    if (imageBytes.isEmpty) {
      debugPrint("OpenAI request failed: Captured image is empty.");
      throw OpenAiException("Captured image is empty.");
    }

    _logKeyDiagnostic();
    debugPrint("OPENAI REQUEST START");
    _lastScannedImageBytes = imageBytes;

    final base64Image = base64Encode(imageBytes);
    if (base64Image.isEmpty) {
      debugPrint("OpenAI request failed: Base64 image encoding resulted in empty string.");
      throw OpenAiException("Captured image is empty.");
    }

    final responseText = await _sendVisionRequest(
      prompt: OpenAiPrompts.documentReaderPrompt,
      base64Image: base64Image,
      maxTokens: 500,
    );

    return _cleanTextForTts(responseText);
  }

  /// Voice Follow-Up: Answer using stored _lastScannedImageBytes
  Future<String> answerFollowUp({
    required Uint8List imageBytes,
    required String question,
    required String intent,
  }) async {
    if (imageBytes.isEmpty) {
      throw OpenAiException("No image scanned yet. Please scan a scene first.");
    }

    _logKeyDiagnostic();
    debugPrint("OPENAI REQUEST START");

    final base64Image = base64Encode(imageBytes);
    final prompt = OpenAiPrompts.followUpQuestionPrompt(
      question: question,
      intent: intent,
    );

    final responseText = await _sendVisionRequest(
      prompt: prompt,
      base64Image: base64Image,
      maxTokens: 300,
    );

    return _cleanTextForTts(responseText);
  }

  Future<String> _sendVisionRequest({
    required String prompt,
    required String base64Image,
    int maxTokens = 300,
  }) async {
    final key = _cleanApiKey;
    if (key.isEmpty || key == "YOUR_OPENAI_API_KEY_HERE") {
      throw OpenAiException("OpenAI authentication failed. Please check OPENAI_API_KEY configuration.");
    }

    final body = jsonEncode({
      "model": openAiModel,
      "messages": [
        {
          "role": "user",
          "content": [
            {
              "type": "text",
              "text": prompt,
            },
            {
              "type": "image_url",
              "image_url": {
                "url": "data:image/jpeg;base64,$base64Image",
              }
            }
          ]
        }
      ],
      "max_tokens": maxTokens,
      "temperature": 0.2,
    });

    final headers = {
      "Authorization": "Bearer $key",
      "Content-Type": "application/json",
    };

    final response = await _postWithRetry(
      Uri.parse("https://api.openai.com/v1/chat/completions"),
      headers,
      body,
    );

    return _extractTextFromOpenAiResponse(response);
  }

  Future<http.Response> _postWithRetry(
    Uri uri,
    Map<String, String> headers,
    String body,
  ) async {
    const int maxRetries = 5;
    final Random random = Random();

    for (int attempt = 1; attempt <= maxRetries + 1; attempt++) {
      try {
        debugPrint("OPENAI request attempt: $attempt");

        final response = await http.post(uri, headers: headers, body: body);

        final statusCode = response.statusCode;
        final responseBody = response.body;

        debugPrint("OPENAI RESPONSE RECEIVED");
        debugPrint("OPENAI HTTP STATUS: $statusCode");
        debugPrint("OPENAI RESPONSE BODY: $responseBody");

        if (statusCode == 200) {
          return response;
        }

        // Non-retryable client status codes
        if (statusCode == 400) {
          String msg = "OpenAI request is invalid.";
          try {
            final decoded = jsonDecode(responseBody);
            final errorMap = decoded['error'];
            if (errorMap is Map && errorMap['message'] != null) {
              msg = "OpenAI request is invalid (400: ${errorMap['message']}).";
            }
          } catch (_) {}
          throw OpenAiException(msg, statusCode: statusCode, responseBody: responseBody);
        } else if (statusCode == 401) {
          throw OpenAiException(
            "OpenAI authentication failed. Please check OPENAI_API_KEY configuration.",
            statusCode: statusCode,
            responseBody: responseBody,
          );
        } else if (statusCode == 403) {
          throw OpenAiException(
            "OpenAI access forbidden (403).",
            statusCode: statusCode,
            responseBody: responseBody,
          );
        } else if (statusCode == 404) {
          throw OpenAiException(
            "OpenAI model unavailable (404).",
            statusCode: statusCode,
            responseBody: responseBody,
          );
        }

        // Retryable status codes: 429, 408, 500, 502, 503, 504
        if (statusCode == 429 ||
            statusCode == 408 ||
            statusCode == 500 ||
            statusCode == 502 ||
            statusCode == 503 ||
            statusCode == 504) {
          if (attempt > maxRetries) {
            final userMsg = statusCode == 429
                ? "OpenAI request limit reached (429). Please try again later."
                : "OpenAI is temporarily unavailable ($statusCode).";
            throw OpenAiException(
              userMsg,
              statusCode: statusCode,
              responseBody: responseBody,
            );
          }
        } else {
          if (attempt > maxRetries) {
            throw OpenAiException(
              "OpenAI is temporarily unavailable ($statusCode).",
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
          "OPENAI attempt $attempt failed with HTTP $statusCode. Waiting ${totalDelayMs}ms before next attempt...",
        );
        await Future.delayed(Duration(milliseconds: totalDelayMs));
      } on SocketException catch (e) {
        debugPrint("OPENAI network exception on attempt $attempt: $e");
        if (attempt > maxRetries) {
          throw OpenAiException("Network connection is unavailable.");
        }
        final delaySec = pow(2, attempt - 1).toInt().clamp(1, 16);
        final totalDelayMs = (delaySec * 1000) + random.nextInt(300);
        await Future.delayed(Duration(milliseconds: totalDelayMs));
      } on TimeoutException catch (e) {
        debugPrint("OPENAI timeout exception on attempt $attempt: $e");
        if (attempt > maxRetries) {
          throw OpenAiException("Network connection is unavailable.");
        }
        final delaySec = pow(2, attempt - 1).toInt().clamp(1, 16);
        final totalDelayMs = (delaySec * 1000) + random.nextInt(300);
        await Future.delayed(Duration(milliseconds: totalDelayMs));
      } catch (e) {
        if (e is OpenAiException) rethrow;
        debugPrint("OPENAI exception on attempt $attempt: $e");
        if (attempt > maxRetries) {
          throw OpenAiException("OpenAI is temporarily unavailable.");
        }
        final delaySec = pow(2, attempt - 1).toInt().clamp(1, 16);
        final totalDelayMs = (delaySec * 1000) + random.nextInt(300);
        await Future.delayed(Duration(milliseconds: totalDelayMs));
      }
    }

    throw OpenAiException("OpenAI is temporarily unavailable.");
  }

  String _extractTextFromOpenAiResponse(http.Response response) {
    if (response.body.trim().isEmpty) {
      throw OpenAiException("OpenAI returned no readable response.");
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (e) {
      throw OpenAiException("OpenAI request is invalid.");
    }

    if (decoded is! Map<String, dynamic>) {
      throw OpenAiException("OpenAI request is invalid.");
    }

    if (decoded.containsKey('error')) {
      final errorMap = decoded['error'];
      final msg = errorMap is Map ? errorMap['message']?.toString() : null;
      debugPrint("OpenAI error object: $msg");

      if (response.statusCode == 401 || (msg != null && msg.contains("Incorrect API key"))) {
        throw OpenAiException("OpenAI authentication failed. Please check OPENAI_API_KEY configuration.");
      } else if (response.statusCode == 429) {
        throw OpenAiException("OpenAI request limit reached (429). Please try again later.");
      }
      throw OpenAiException(msg ?? "OpenAI request failed.");
    }

    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) {
      throw OpenAiException("OpenAI returned no readable response.");
    }

    final firstChoice = choices.first;
    if (firstChoice is! Map<String, dynamic>) {
      throw OpenAiException("OpenAI returned no readable response.");
    }

    final message = firstChoice['message'];
    if (message is! Map<String, dynamic>) {
      throw OpenAiException("OpenAI returned no readable response.");
    }

    final content = message['content'];
    if (content == null || content.toString().trim().isEmpty) {
      throw OpenAiException("OpenAI returned no readable response.");
    }

    return content.toString().trim();
  }

  String _cleanTextForTts(String text) {
    return text
        .replaceAll(RegExp(r'[*#_`]'), '')
        .replaceAll(RegExp(r'^\s*[-*]\s+', multiLine: true), '')
        .replaceAll(RegExp(r'\n+'), ' ')
        .trim();
  }
}
