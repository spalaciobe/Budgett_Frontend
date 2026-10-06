# MediaPipe's GenAI runtime is generated from protobuf, and the generated
# classes carry annotations (ProtoField, ProtoPresenceBits, …) that live in a
# protobuf artifact it does not depend on. R8 refuses to finish while they are
# missing, so the release build fails on a reference that is never followed at
# runtime.
#
# Without this the APK builds in debug and fails in CI, which is where the
# signed release is made.
-dontwarn com.google.protobuf.**
-keep class com.google.mediapipe.** { *; }
-keep class com.google.mediapipe.tasks.genai.** { *; }

# tasks-genai also declares an image input path (LlmInferenceSession.addImage)
# whose classes live in tasks-vision. This app never uses it — the OCR is ML
# Kit's job and the model is handed TEXT — so the vision artifact is not a
# dependency, and the references R8 finds are to methods that are never
# called. Pulling in tasks-vision to satisfy them would add tens of megabytes
# to an APK that is downloaded over the air on every release.
-dontwarn com.google.mediapipe.framework.image.**
-dontwarn com.google.mediapipe.**

# ML Kit loads its text recogniser through reflection on the options class,
# so the names have to survive minification.
-keep class com.google.mlkit.** { *; }
-dontwarn com.google.mlkit.**

# Both libraries reach native code through JNI; a renamed method is a crash at
# the boundary rather than a build error.
-keepclasseswithmembernames class * {
    native <methods>;
}
