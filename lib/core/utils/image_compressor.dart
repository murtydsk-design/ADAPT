import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

abstract class ImageCompressor {
  /// Compresses and resizes raw camera image bytes for mobile vision AI processing.
  /// Resizes image to maxDimension 1024px and encodes as JPEG (quality 82).
  /// Reduces payload size from ~4MB to ~100-150KB for faster network transmission.
  static Future<Uint8List> compressForVision(
    Uint8List inputBytes, {
    int maxDimension = 1024,
    int quality = 82,
  }) async {
    try {
      return await compute(_processImageIsolate, {
        'bytes': inputBytes,
        'maxDimension': maxDimension,
        'quality': quality,
      });
    } catch (e) {
      debugPrint("Image compression fallback: $e");
      return inputBytes;
    }
  }

  static Uint8List _processImageIsolate(Map<String, dynamic> params) {
    final Uint8List bytes = params['bytes'];
    final int maxDimension = params['maxDimension'];
    final int quality = params['quality'];

    final decoded = img.decodeImage(bytes);
    if (decoded == null) return bytes;

    if (decoded.width <= maxDimension && decoded.height <= maxDimension) {
      return Uint8List.fromList(img.encodeJpg(decoded, quality: quality));
    }

    img.Image resized;
    if (decoded.width >= decoded.height) {
      resized = img.copyResize(decoded, width: maxDimension);
    } else {
      resized = img.copyResize(decoded, height: maxDimension);
    }

    return Uint8List.fromList(img.encodeJpg(resized, quality: quality));
  }
}
