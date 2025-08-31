# Add project specific ProGuard rules here.
# You can find more samples at
# https://developer.android.com/studio/build/shrink-code.html#optimization-samples

# Flutter TFLite Plugin
-keep class org.tensorflow.lite.** { *; }
-dontwarn org.tensorflow.lite.**