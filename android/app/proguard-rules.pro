# Keep Flutter / Dart related classes
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# Keep Firebase
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**

# Keep Kotlin metadata
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes InnerClasses
-keepattributes EnclosingMethod

# Keep model classes
-keep class com.livelocation.app.** { *; }

# Fix: R8 missing class errors for Play Core (not used by this app but
# referenced by Flutter's deferred components infrastructure).
-dontwarn com.google.android.play.core.splitcompat.**
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.**
-keep class com.google.android.play.core.** { *; }

# Fix: Keep classes needed by Firebase and background service
-keep class com.google.firebase.database.** { *; }
-keep class id.flutter.flutter_background_service_android.** { *; }

# Fix: Keep classes needed by geolocator and other plugins
-keep class com.baseflow.** { *; }
-keep class com.lyokone.location.** { *; }

# Fix: Keep notification classes
-keep class com.dexterous.** { *; }

# General fixes for Flutter release builds
-dontwarn javax.lang.model.element.**
-dontwarn javax.lang.model.type.**
-dontwarn javax.lang.model.util.**
