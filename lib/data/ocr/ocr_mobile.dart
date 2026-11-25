import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

bool get ocrAvailable => defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;

/// ML Kit (Google), modelo latino incluido en la app: funciona sin internet.
Future<String> recognizeText(XFile image) async {
  if (!ocrAvailable) throw UnsupportedError('Lectura de texto no disponible en esta plataforma.');
  final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
  try {
    final result = await recognizer.processImage(InputImage.fromFilePath(image.path));
    // Una línea por renglón detectado, en orden de lectura.
    return [for (final b in result.blocks) for (final l in b.lines) l.text].join('\n');
  } finally {
    await recognizer.close();
  }
}
