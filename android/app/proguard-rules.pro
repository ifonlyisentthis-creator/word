# Flutter-specific ProGuard rules
# Keep Flutter engine classes
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }

# Keep Firebase classes
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**

# Keep Google Sign-In classes
-keep class com.google.android.gms.auth.** { *; }
-keep class com.google.android.gms.common.** { *; }
-dontwarn com.google.android.gms.**

# Keep RevenueCat classes
-keep class com.revenuecat.purchases.** { *; }
-dontwarn com.revenuecat.purchases.**

# Keep flutter_secure_storage
-keep class com.it_nomads.fluttersecurestorage.** { *; }

# Keep local_auth
-keep class io.flutter.plugins.localauth.** { *; }

# Keep/suppress Play Core split-install classes (referenced by Flutter engine)
-dontwarn com.google.android.play.core.splitcompat.**
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**

# Suppress warnings for missing annotations
-dontwarn javax.annotation.**
-dontwarn kotlin.Metadata
