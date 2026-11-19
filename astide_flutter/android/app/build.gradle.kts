import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}

val pubspecFile = rootProject.file("../pubspec.yaml")
val appVersionDartFile = rootProject.file("../lib/app_version.dart")
val requestedTasks = gradle.startParameter.taskNames.map { it.lowercase() }
val isReleasePackaging = requestedTasks.any {
    it.endsWith("assemblerelease") ||
        it.endsWith("bundlerelease") ||
        it.endsWith("packagerelease") ||
        it == "assemble" ||
        it == "bundle"
}
val skipVersionBump = project.findProperty("noBumpVersion")?.toString()?.toBoolean() == true
val isSplitPerAbi = project.findProperty("split-per-abi")?.toString()?.toBoolean() == true

// Default Android release builds to pure 64-bit arm64-v8a (skip compiling 32-bit & x86_64 targets).
if (isReleasePackaging && !project.hasProperty("target-platform") && !isSplitPerAbi) {
    project.extensions.extraProperties["target-platform"] = "android-arm64"
}

var resolvedVersionName: String? = null
var resolvedVersionCode: Int? = null

if (pubspecFile.exists()) {
    val rawPubspec = pubspecFile.readText(Charsets.UTF_8)
    val versionLineRegex = Regex("""(?m)^version:\s*(\d+)\.(\d+)\.(\d+)(?:\+(\d+))?([ \t]*\r?)$""")
    val match = versionLineRegex.find(rawPubspec)
    if (match != null) {
        val major = match.groupValues[1].toInt()
        val minor = match.groupValues[2].toInt()
        var patch = match.groupValues[3].toInt()
        var buildNum = match.groupValues[4].toIntOrNull() ?: 1
        val trailing = match.groupValues[5]

        if (isReleasePackaging && !skipVersionBump) {
            patch += 1
            buildNum += 1
            val nextVersionName = "$major.$minor.$patch"
            val updatedPubspec = rawPubspec.replaceRange(
                match.range,
                "version: $nextVersionName+$buildNum$trailing",
            )
            pubspecFile.writeText(updatedPubspec, Charsets.UTF_8)
            appVersionDartFile.writeText(
                "/// Auto-synced with `pubspec.yaml` during Android release packaging.\n" +
                    "const String kAppVersion = '$nextVersionName';\n",
                Charsets.UTF_8,
            )
            println("Astide release version auto-bumped -> $nextVersionName+$buildNum")
        }

        resolvedVersionName = "$major.$minor.$patch"
        resolvedVersionCode = buildNum
    }
}

android {
    namespace = "com.hoilai.mm.astide"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.hoilai.mm.astide"
        minSdk = maxOf(flutter.minSdkVersion, 24)
        targetSdk = flutter.targetSdkVersion
        versionCode = resolvedVersionCode ?: flutter.versionCode
        versionName = resolvedVersionName ?: flutter.versionName
    }

    signingConfigs {
        create("release") {
            val storePath = keystoreProperties.getProperty("storeFile")
            if (!storePath.isNullOrBlank()) {
                storeFile = rootProject.file(storePath)
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Pure 64-bit Android APK: drop 32-bit (armeabi-v7a / x86) and desktop x86_64 ABIs.
            if (!isSplitPerAbi) {
                ndk {
                    abiFilters.clear()
                    abiFilters += listOf("arm64-v8a")
                }
            }
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

androidComponents {
    onVariants(selector().withBuildType("release")) { variant ->
        if (!isSplitPerAbi) {
            variant.packaging.jniLibs.excludes.addAll(
                "**/armeabi/**",
                "**/armeabi-v7a/**",
                "**/x86/**",
                "**/x86_64/**",
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
