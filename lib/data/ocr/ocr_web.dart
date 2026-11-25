import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:image_picker/image_picker.dart';

/// Tesseract.js servido desde la propia app (web/tesseract/, ver
/// tool/fetch_ocr_web.sh): el reconocimiento ocurre en el navegador.
extension type _Worker(JSObject _) implements JSObject {
  external JSPromise<JSObject> recognize(JSAny image);
  external JSPromise<JSAny?> terminate();
}

JSObject? get _tesseract => globalContext.getProperty<JSObject?>('Tesseract'.toJS);

bool get ocrAvailable => _tesseract != null;

Future<String> recognizeText(XFile image) async {
  final t = _tesseract;
  if (t == null) throw UnsupportedError('El lector de texto no se cargó en esta página.');
  final base = Uri.base.resolve('tesseract/').toString();
  final options = {
    'workerPath': '${base}worker.min.js',
    'corePath': '${base}core',
    'langPath': '${base}lang',
    'gzip': true,
  }.jsify()!;
  final worker = _Worker(await t.callMethod<JSPromise<JSObject>>('createWorker'.toJS, 'spa'.toJS, 1.toJS, options).toDart);
  try {
    final bytes = await image.readAsBytes();
    final mime = image.mimeType ?? 'image/png';
    final dataUrl = 'data:$mime;base64,${base64Encode(bytes)}';
    final result = await worker.recognize(dataUrl.toJS).toDart;
    final data = result.getProperty<JSObject>('data'.toJS);
    return data.getProperty<JSString>('text'.toJS).toDart;
  } finally {
    await worker.terminate().toDart;
  }
}
