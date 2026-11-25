import 'package:image_picker/image_picker.dart';

import 'ocr_stub.dart' if (dart.library.js_interop) 'ocr_web.dart' if (dart.library.io) 'ocr_mobile.dart' as impl;

/// Lee el texto de una imagen DENTRO del dispositivo (la imagen no se envía
/// a ningún servidor): ML Kit en Android y Tesseract en el navegador.
Future<String> recognizeText(XFile image) => impl.recognizeText(image);

/// true si este dispositivo puede leer texto de imágenes.
bool get ocrAvailable => impl.ocrAvailable;
