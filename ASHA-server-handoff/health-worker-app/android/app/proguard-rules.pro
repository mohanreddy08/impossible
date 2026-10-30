# ONNX Runtime (offline Telugu speech, TeluguAsr.kt): its native code finds these Java classes BY NAME through JNI. If the release
# build's shrinker renames or removes them the app aborts with "JNI DETECTED ERROR ... java_class == null" the first time the model runs.
-keep class ai.onnxruntime.** { *; }
-keepclassmembers class ai.onnxruntime.** { *; }
