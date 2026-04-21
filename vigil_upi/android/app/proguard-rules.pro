# VigilUPI ProGuard Rules
#
# SECURITY: Keep TFLite inference classes — stripping them breaks on-device AI
-keep class org.tensorflow.** { *; }
-keep class org.tensorflow.lite.** { *; }
-dontwarn org.tensorflow.**

# Keep UPI India SDK classes intact for intent resolution
-keep class com.upi.** { *; }
-dontwarn com.upi.**

# Flutter embedding
-keep class io.flutter.** { *; }
-keep class io.flutter.embedding.** { *; }

# Hive — keep generated adapters
-keep class * extends com.google.flatbuffers.Table { *; }
-keep class * implements com.google.flatbuffers.FlatBufferBuilder { *; }
