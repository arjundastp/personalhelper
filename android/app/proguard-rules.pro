# MSAL (Microsoft sign-in) uses reflection and Gson; keep it intact.
-keep class com.microsoft.identity.** { *; }
-keep class com.microsoft.device.display.** { *; }
# Optional crypto providers MSAL can use but we don't ship.
-dontwarn com.google.crypto.tink.**
-dontwarn com.microsoft.device.display.**
-dontwarn org.bouncycastle.**
-dontwarn edu.umd.cs.findbugs.annotations.**
