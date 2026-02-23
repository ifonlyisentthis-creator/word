# =============================================================================
# Afterword — Comprehensive ProGuard / R8 Rules for Release Builds
# =============================================================================

# ── Flutter Engine ──────────────────────────────────────────────────────
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.embedding.** { *; }

# ── Firebase (Core + Messaging / FCM) ──────────────────────────────────
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**
# Firebase Messaging needs its reflection-based service
-keep class com.google.firebase.messaging.FirebaseMessagingService { *; }
-keep class com.google.firebase.iid.** { *; }

# ── Google Sign-In ─────────────────────────────────────────────────────
-keep class com.google.android.gms.auth.** { *; }
-keep class com.google.android.gms.common.** { *; }

# ── RevenueCat ─────────────────────────────────────────────────────────
-keep class com.revenuecat.purchases.** { *; }
-dontwarn com.revenuecat.purchases.**

# ── Supabase / OkHttp / Ktor (transitive via supabase_flutter) ────────
-keep class io.github.jan.supabase.** { *; }
-dontwarn io.github.jan.supabase.**
-keep class io.ktor.** { *; }
-dontwarn io.ktor.**
-keep class okhttp3.** { *; }
-keep class okio.** { *; }
-dontwarn okhttp3.**
-dontwarn okio.**
# OkHttp uses reflection for platform detection
-dontwarn org.conscrypt.**
-dontwarn org.bouncycastle.**
-dontwarn org.openjsse.**

# ── google_fonts (runtime font loading via OkHttp) ────────────────────
-keep class io.flutter.plugins.googlemobilefonts.** { *; }

# ── just_audio / ExoPlayer (media playback) ───────────────────────────
-keep class com.google.android.exoplayer2.** { *; }
-keep class androidx.media3.** { *; }
-dontwarn com.google.android.exoplayer2.**
-dontwarn androidx.media3.**
-keep class com.ryanheise.just_audio.** { *; }

# ── record (audio recording) ──────────────────────────────────────────
-keep class com.llfbandit.record.** { *; }

# ── flutter_local_notifications ────────────────────────────────────────
-keep class com.dexterous.** { *; }
-dontwarn com.dexterous.**

# ── flutter_secure_storage ─────────────────────────────────────────────
-keep class com.it_nomads.fluttersecurestorage.** { *; }
# EncryptedSharedPreferences backend (Android Keystore)
-keep class androidx.security.crypto.** { *; }
-dontwarn androidx.security.crypto.**
# Tink is the internal crypto engine for AndroidX Security
-keep class com.google.crypto.tink.** { *; }
-dontwarn com.google.crypto.tink.**

# ── local_auth (biometric) ─────────────────────────────────────────────
-keep class io.flutter.plugins.localauth.** { *; }
-keep class androidx.biometric.** { *; }

# ── permission_handler ─────────────────────────────────────────────────
-keep class com.baseflow.permissionhandler.** { *; }

# ── url_launcher ───────────────────────────────────────────────────────
-keep class io.flutter.plugins.urllauncher.** { *; }

# ── path_provider ──────────────────────────────────────────────────────
-keep class io.flutter.plugins.pathprovider.** { *; }

# ── cryptography / BouncyCastle (encryption) ───────────────────────────
-keep class org.bouncycastle.** { *; }
-dontwarn org.bouncycastle.**

# ── Kotlin ─────────────────────────────────────────────────────────────
-keep class kotlin.Metadata { *; }
-keep class kotlinx.serialization.** { *; }
-dontwarn kotlinx.serialization.**
-keep class kotlin.reflect.** { *; }
-dontwarn kotlin.reflect.**

# ── AndroidX / Material / Lifecycle / Fragment ───────────────────────
-keep class androidx.core.app.** { *; }
-keep class androidx.window.** { *; }
-dontwarn androidx.window.**
# Lifecycle (Firebase, Google Sign-In, local_auth)
-keep class androidx.lifecycle.** { *; }
-dontwarn androidx.lifecycle.**
# Fragment (Google Sign-In Activity, local_auth BiometricPrompt)
-keep class androidx.fragment.** { *; }
-dontwarn androidx.fragment.**

# ── Play Core (referenced by Flutter engine) ──────────────────────────
-dontwarn com.google.android.play.core.splitcompat.**
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**

# ── General safety ─────────────────────────────────────────────────────
-dontwarn javax.annotation.**
-dontwarn java.lang.invoke.**
-dontwarn sun.misc.Unsafe

# Keep native methods (JNI)
-keepclasseswithmembernames class * { native <methods>; }

# Keep Parcelable implementations
-keep class * implements android.os.Parcelable { *; }

# Keep Serializable classes
-keepclassmembers class * implements java.io.Serializable {
    static final long serialVersionUID;
    private static final java.io.ObjectStreamField[] serialPersistentFields;
    private void writeObject(java.io.ObjectOutputStream);
    private void readObject(java.io.ObjectInputStream);
    java.lang.Object writeReplace();
    java.lang.Object readResolve();
}

# Keep enums (needed by Kotlin/serialization)
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}
