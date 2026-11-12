# shared_preferences_android 2.5 appelle son code Kotlin par JNI (Pigeon JNI,
# paquet `jni`) en cherchant classes et méthodes par leur nom. En release, R8
# renomme ces classes Kotlin (Continuation devient « E5/d ») : toute lecture ou
# écriture échoue alors (NoSuchMethodError) — onboarding revu à chaque
# lancement, lieux récents et langue perdus. On garde ces noms intacts.

# Le plugin lui-même.
-keep class io.flutter.plugins.sharedpreferences.** { *; }

# Classes Kotlin cherchées par nom depuis Dart (jni/lib/src/kotlin.dart).
-keep class kotlin.coroutines.Continuation { *; }
-keep class kotlin.coroutines.intrinsics.** { *; }
-keep class kotlin.Result { *; }
-keep class kotlin.Result$Failure { *; }
-keep class kotlin.Unit { *; }
