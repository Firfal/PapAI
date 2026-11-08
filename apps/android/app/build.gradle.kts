import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

// Signature de l'APK distribué hors store : la même clé à chaque version, sinon
// Android refuse la mise à jour. La clé n'est jamais dans le dépôt : chemin et
// mots de passe dans keystore.properties (ignoré par git) ou dans l'environnement.
val signing = Properties().apply {
    val f = rootProject.file("keystore.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
fun sign(key: String): String? = signing.getProperty(key) ?: System.getenv("PAPAI_" + key.uppercase())

// Démo sans EMM : jeton support et serveur dans support.local.properties (ignoré par git,
// voir support.local.properties.example). Absent : chaînes vides, l'app attend la
// configuration gérée. Le jeton est alors inclus dans l'APK : ne pas le diffuser.
val support = Properties().apply {
    val f = rootProject.file("support.local.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
fun supportField(key: String): String =
    "\"" + (support.getProperty(key) ?: "").trim().replace("\\", "\\\\").replace("\"", "\\\"") + "\""

android {
    namespace = "com.quentin.papai.aidant"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.quentin.papai.aidant"
        minSdk = 26
        targetSdk = 35
        versionCode = 1
        versionName = "1.0"
        buildConfigField("String", "PAPAI_SUPPORT_TOKEN", supportField("supportToken"))
        buildConfigField("String", "PAPAI_SERVER", supportField("server"))
    }

    signingConfigs {
        val store = sign("keystore")
        if (store != null) {
            create("release") {
                storeFile = file(store)
                storePassword = sign("keystore_password")
                keyAlias = sign("key_alias") ?: "papai"
                keyPassword = sign("key_password") ?: sign("keystore_password")
            }
        }
    }

    buildTypes {
        debug { manifestPlaceholders["cleartextTraffic"] = "true" }
        release {
            manifestPlaceholders["cleartextTraffic"] = "false"
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
            if (signingConfig == signingConfigs.getByName("debug")) {
                logger.warn("ATTENTION — APK release signé avec la clé de DEBUG : configurez une clé de distribution avant diffusion.")
            }
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
    buildFeatures { compose = true; buildConfig = true }
}

dependencies {
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20240303")
    val composeBom = platform("androidx.compose:compose-bom:2024.09.03")
    implementation(composeBom)
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.activity:activity-compose:1.9.2")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.8.6")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
}
