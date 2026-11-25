import 'package:image_picker/image_picker.dart';

bool get ocrAvailable => false;
Future<String> recognizeText(XFile image) => throw UnsupportedError('Lectura de texto no disponible en esta plataforma.');
