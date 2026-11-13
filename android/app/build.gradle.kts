import java.util.Properties

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

val keyProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}

fun signingValue(env: String, property: String): String? =
    System.getenv(env)?.takeIf { it.isNotBlank() }
        ?: keyProperties.getProperty(property)?.takeIf { it.isNotBlank() }

val releaseStoreFile = signingValue("TT_RELEASE_STORE_FILE", "storeFile")
val releaseStorePassword = signingValue("TT_RELEASE_STORE_PASSWORD", "storePassword")
val releaseKeyAlias = signingValue("TT_RELEASE_KEY_ALIAS", "keyAlias")
val releaseKeyPassword = signingValue("TT_RELEASE_KEY_PASSWORD", "keyPassword")
val hasReleaseSigning = listOf(
    releaseStoreFile, releaseStorePassword, releaseKeyAlias, releaseKeyPassword,
).all { it != null }

val singleAbi: String? = System.getenv("TT_ABI_FILTER")?.trim()?.takeIf { it.isNotEmpty() }

val devApp: Boolean = !System.getenv("TT_DEV_APP").isNullOrBlank()

fun versionCodeOf(name: String): Int {
    val parts = Regex("""(\d{1,3})\.(\d{1,2})\.(\d{1,2})(?:-beta\.([1-9]|[1-8]\d|9[0-8]))?""")
        .matchEntire(name)?.groupValues
        ?: throw GradleException("Version $name is not X.Y.Z or X.Y.Z-beta.N with N from 1 to 98")
    val stage = parts[4].toIntOrNull() ?: 99
    return parts[1].toInt() * 1_000_000 + parts[2].toInt() * 10_000 + parts[3].toInt() * 100 + stage
}

android {
    namespace = "org.gozaltech.teamtalkx"
    compileSdk = 37
    ndkVersion = "30.0.16248370"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "org.gozaltech.teamtalkx"
        minSdk = 29
        targetSdk = flutter.targetSdkVersion
        versionCode = versionCodeOf(flutter.versionName)
        versionName = flutter.versionName
        manifestPlaceholders["appLabel"] = if (devApp) "TeamTalkX dev" else "TeamTalkX"
        if (devApp) applicationIdSuffix = ".dev"
        if (singleAbi != null) {
            ndk {
                abiFilters.clear()
                abiFilters.add(singleAbi)
            }
        }
    }

    externalNativeBuild {
        cmake {
            path = file("../../native/CMakeLists.txt")
            version = "4.1.2"
        }
    }

    if (singleAbi == null) {
        splits {
            abi {
                isEnable = true
                reset()
                include("arm64-v8a", "armeabi-v7a", "x86_64")
                isUniversalApk = true
            }
        }
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = rootProject.file(releaseStoreFile!!)
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
                enableV3Signing = true
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                null
            }
        }
    }

    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }

    applicationVariants.all {
        val variant = this
        outputs.all {
            val output = this as com.android.build.gradle.internal.api.BaseVariantOutputImpl
            val abi = output.filters
                .firstOrNull { it.filterType == com.android.build.OutputFile.ABI }
                ?.identifier
                ?: (singleAbi ?: "universal")
            output.outputFileName =
                "TeamTalkX-${variant.versionName}-$abi.apk"
        }
    }
}

tasks.matching { it.name.startsWith("package") && it.name.endsWith("Release") }
    .configureEach {
        doFirst {
            if (!hasReleaseSigning) {
                throw GradleException(
                    "Release signing is not configured. Set TT_RELEASE_STORE_FILE, " +
                        "TT_RELEASE_STORE_PASSWORD, TT_RELEASE_KEY_ALIAS and " +
                        "TT_RELEASE_KEY_PASSWORD, or create android/key.properties. " +
                        "The four values come from the release keystore.",
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

dependencies {
    implementation("androidx.core:core-ktx:1.19.1")
    implementation("androidx.media:media:1.8.0")
}
