import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

class TtsService {
  final FlutterTts _tts = FlutterTts();
  int _speakSessionId = 0;

  Future<void> init() async {
    await _tts.setLanguage("en-US");
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
    await _tts.awaitSpeakCompletion(true);
  }

  Future<void> speak(String text) async {
    _speakSessionId++;
    final currentSession = _speakSessionId;

    await _tts.stop();

    final chunks = _splitTextIntoChunks(text);
    final int totalLength = chunks.fold<int>(0, (sum, c) => sum + c.length);

    debugPrint("TTS TEXT LENGTH: ${text.length}");
    debugPrint("TTS CHUNKS: ${chunks.length}");
    debugPrint("TTS INPUT TOTAL LENGTH: $totalLength");

    for (final chunk in chunks) {
      if (_speakSessionId != currentSession) return;
      if (chunk.isNotEmpty) {
        await _tts.speak(chunk);
      }
    }
  }

  Future<void> stop() async {
    _speakSessionId++;
    await _tts.stop();
  }

  Future<void> setRate(double rate) async {
    await _tts.setSpeechRate(rate);
  }

  Future<void> setPitch(double pitch) async {
    await _tts.setPitch(pitch);
  }

  Future<void> setVolume(double volume) async {
    await _tts.setVolume(volume);
  }

  List<String> _splitTextIntoChunks(String text, {int maxChunkLength = 200}) {
    final cleaned = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.isEmpty) return [];

    if (cleaned.length <= maxChunkLength) {
      return [cleaned];
    }

    final RegExp sentenceEnd = RegExp(r'(?<=[.!?])\s+');
    final List<String> sentences = cleaned.split(sentenceEnd);

    final List<String> chunks = [];
    String currentChunk = "";

    for (final sentence in sentences) {
      final trimmedSentence = sentence.trim();
      if (trimmedSentence.isEmpty) continue;

      if (trimmedSentence.length > maxChunkLength) {
        if (currentChunk.isNotEmpty) {
          chunks.add(currentChunk.trim());
          currentChunk = "";
        }

        final words = trimmedSentence.split(' ');
        for (final word in words) {
          if ((currentChunk.isEmpty ? word : "$currentChunk $word").length > maxChunkLength) {
            if (currentChunk.isNotEmpty) {
              chunks.add(currentChunk.trim());
            }
            currentChunk = word;
          } else {
            currentChunk = currentChunk.isEmpty ? word : "$currentChunk $word";
          }
        }
      } else {
        if ((currentChunk.isEmpty ? trimmedSentence : "$currentChunk $trimmedSentence").length > maxChunkLength) {
          chunks.add(currentChunk.trim());
          currentChunk = trimmedSentence;
        } else {
          currentChunk = currentChunk.isEmpty ? trimmedSentence : "$currentChunk $trimmedSentence";
        }
      }
    }

    if (currentChunk.isNotEmpty) {
      chunks.add(currentChunk.trim());
    }

    return chunks;
  }
}
