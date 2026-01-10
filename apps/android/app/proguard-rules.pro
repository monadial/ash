# ASH ProGuard Rules

# Keep UniFFI generated classes
-keep class com.monadial.ash.core.** { *; }
-keep class uniffi.** { *; }

# Keep JNA classes
-keep class com.sun.jna.** { *; }
-keep class * implements com.sun.jna.** { *; }

# Keep Kotlin serialization
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.AnnotationsKt

-keepclassmembers class kotlinx.serialization.json.** {
    *** Companion;
}
-keepclasseswithmembers class kotlinx.serialization.json.** {
    kotlinx.serialization.KSerializer serializer(...);
}

-keep,includedescriptorclasses class com.monadial.ash.**$$serializer { *; }
-keepclassmembers class com.monadial.ash.** {
    *** Companion;
}
-keepclasseswithmembers class com.monadial.ash.** {
    kotlinx.serialization.KSerializer serializer(...);
}
