# ML Kit (lectura de capturas): solo se incluye el modelo de alfabeto latino.
# Los reconocedores de chino, devanagari, japonés y coreano no se empaquetan
# a propósito; el plugin los referencia, así que se indica a R8 que no los busque.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# ML Kit carga sus componentes por nombre (registrars declarados en el
# manifiesto). Si R8 los renombra o elimina, el lector falla con
# «NullPointerException ... getClass() on a null object reference».
-keep class com.google.mlkit.** { *; }
-keep class com.google_mlkit_text_recognition.** { *; }
-keep class com.google_mlkit_commons.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_text_common.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_common.** { *; }
-keep class com.google.android.gms.internal.mlkit_common.** { *; }
-keep class com.google.firebase.components.** { *; }
-keep class * implements com.google.firebase.components.ComponentRegistrar { *; }
-dontwarn com.google.firebase.components.**
