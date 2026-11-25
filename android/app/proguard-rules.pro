# ML Kit (lectura de capturas): solo se incluye el modelo de alfabeto latino.
# Los reconocedores de chino, devanagari, japonés y coreano no se empaquetan
# a propósito; el plugin los referencia, así que se indica a R8 que no los busque.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
