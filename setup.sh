#!/bin/bash
set -e

# 1. Bikin folder project
mkdir -p app/src/main/java/com/c666/stealthoverlay
mkdir -p .github/workflows

# 2. File Gradle (Fixed Version)
cat << 'EOF' > settings.gradle.kts
pluginManagement {
    repositories { google(); mavenCentral(); gradlePluginPortal() }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories { google(); mavenCentral() }
}
rootProject.name = "StealthOverlay"
include(":app")
EOF

cat << 'EOF' > build.gradle.kts
plugins {
    id("com.android.application") version "8.2.2" apply false
    id("org.jetbrains.kotlin.android") version "1.9.22" apply false
}
EOF

cat << 'EOF' > gradle.properties
org.gradle.jvmargs=-Xmx2048m -Dfile.encoding=UTF-8
android.useAndroidX=true
android.nonTransitiveRClass=true
EOF

mkdir -p gradle/wrapper
cat << 'EOF' > gradle/wrapper/gradle-wrapper.properties
distributionUrl=https\://services.gradle.org/distributions/gradle-8.2-bin.zip
EOF

cat << 'EOF' > app/build.gradle.kts
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}
android {
    namespace = "com.c666.stealthoverlay"
    compileSdk = 34
    defaultConfig {
        applicationId = "com.c666.stealthoverlay"
        minSdk = 26
        targetSdk = 34
        versionCode = 1
        versionName = "1.0"
    }
    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
}
dependencies {
    implementation("androidx.core:core-ktx:1.12.0")
    implementation("androidx.appcompat:appcompat:1.6.1")
    implementation("com.google.android.material:material:1.11.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")
}
EOF

# 3. Manifest
cat << 'EOF' > app/src/main/AndroidManifest.xml
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.SYSTEM_ALERT_WINDOW"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_SPECIAL_USE"/>
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
    <application
        android:allowBackup="false"
        android:icon="@android:drawable/ic_menu_search"
        android:label="Sistem"
        android:theme="@style/Theme.AppCompat.DayNight.NoActionBar">
        <activity android:name=".MainActivity" android:exported="true" android:excludeFromRecents="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
        <service android:name=".OverlayService" android:exported="false" android:foregroundServiceType="specialUse">
            <property android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE" android:value="system_helper"/>
        </service>
    </application>
</manifest>
EOF

# 4. MainActivity.kt
cat << 'EOF' > app/src/main/java/com/c666/stealthoverlay/MainActivity.kt
package com.c666.stealthoverlay

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity

class MainActivity : AppCompatActivity() {
    private lateinit var store: AnswerStore

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        store = AnswerStore(this)

        val layout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(50, 50, 50, 50)
        }

        val btnPerm = Button(this).apply { text = "1. Kasih Izin Overlay" }
        val inputJson = EditText(this).apply {
            hint = "Format: [{\"soal\":\"1+1\",\"jawab\":\"2\"}]"
            minLines = 5
        }
        val btnSave = Button(this).apply { text = "2. Simpan Data" }
        val btnStart = Button(this).apply { text = "3. Mulai Overlay" }

        btnPerm.setOnClickListener {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {
                startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName")))
            } else {
                Toast.makeText(this, "Izin sudah ada", Toast.LENGTH_SHORT).show()
            }
        }

        btnSave.setOnClickListener {
            if (store.saveRawData(inputJson.text.toString())) {
                Toast.makeText(this, "Tersimpan", Toast.LENGTH_SHORT).show()
            } else {
                Toast.makeText(this, "Format salah", Toast.LENGTH_SHORT).show()
            }
        }

        btnStart.setOnClickListener {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {
                Toast.makeText(this, "Kasih izin dulu!", Toast.LENGTH_SHORT).show()
            } else {
                startForegroundService(Intent(this, OverlayService::class.java))
                Toast.makeText(this, "Bubble muncul", Toast.LENGTH_SHORT).show()
            }
        }

        layout.addView(btnPerm)
        layout.addView(inputJson)
        layout.addView(btnSave)
        layout.addView(btnStart)
        setContentView(layout)
    }
}
EOF

# 5. AnswerStore.kt
cat << 'EOF' > app/src/main/java/com/c666/stealthoverlay/AnswerStore.kt
package com.c666.stealthoverlay

import android.content.Context
import org.json.JSONArray
import java.io.File

class AnswerStore(private val context: Context) {
    private val file = File(context.filesDir, "jawaban.json")

    fun saveRawData(jsonString: String): Boolean {
        return try {
            JSONArray(jsonString)
            file.writeText(jsonString)
            true
        } catch (e: Exception) { false }
    }

    fun search(query: String): String {
        if (!file.exists()) return "Data kosong."
        return try {
            val array = JSONArray(file.readText())
            val q = query.lowercase().trim()
            for (i in 0 until array.length()) {
                val obj = array.getJSONObject(i)
                val soal = obj.getString("soal").lowercase()
                if (q.contains(soal) || soal.contains(q)) return obj.getString("jawab")
            }
            "Tidak ditemukan."
        } catch (e: Exception) { "Error baca data." }
    }
}
EOF

# 6. OverlayService.kt
cat << 'EOF' > app/src/main/java/com/c666/stealthoverlay/OverlayService.kt
package com.c666.stealthoverlay

import android.app.*
import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.os.Build
import android.os.IBinder
import android.view.*
import android.widget.*
import androidx.core.app.NotificationCompat

class OverlayService : Service() {
    private lateinit var windowManager: WindowManager
    private lateinit var store: AnswerStore
    private var bubbleView: View? = null
    private var panelView: View? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        store = AnswerStore(this)
        startForeground(1, buildNotification())
        showBubble()
    }

    private fun showBubble() {
        val v = FrameLayout(this).apply { setBackgroundColor(0x88000000.toInt()) }
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY else WindowManager.LayoutParams.TYPE_PHONE
        val params = WindowManager.LayoutParams(80, 80, type, WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE, PixelFormat.TRANSLUCENT).apply {
            gravity = Gravity.TOP or Gravity.START; x = 100; y = 200
        }

        var downX = 0; var downY = 0; var startX = 0; var startY = 0

        v.setOnTouchListener { _, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> { downX = event.rawX.toInt(); downY = event.rawY.toInt(); startX = params.x; startY = params.y; true }
                MotionEvent.ACTION_MOVE -> { params.x = startX + (event.rawX.toInt() - downX); params.y = startY + (event.rawY.toInt() - downY); windowManager.updateViewLayout(v, params); true }
                MotionEvent.ACTION_UP -> { showPanel(); true }
                else -> false
            }
        }
        windowManager.addView(v, params)
        bubbleView = v
    }

    private fun showPanel() {
        if (panelView != null) return
        val layout = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setBackgroundColor(0xEE1E1E1E.toInt()); setPadding(30, 30, 30, 30) }
        val input = EditText(this).apply { hint = "Ketik soal..."; setTextColor(0xFFFFFFFF.toInt()) }
        val btnSearch = Button(this).apply { text = "Cari" }
        val btnClose = Button(this).apply { text = "Tutup" }
        val result = TextView(this).apply { setTextColor(0xFF00FF00.toInt()); textSize = 18f; setPadding(0, 20, 0, 20) }

        btnSearch.setOnClickListener { result.text = store.search(input.text.toString()) }
        btnClose.setOnClickListener { hidePanel() }

        layout.addView(input); layout.addView(btnSearch); layout.addView(result); layout.addView(btnClose)

        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY else WindowManager.LayoutParams.TYPE_PHONE
        val params = WindowManager.LayoutParams(WindowManager.LayoutParams.WRAP_CONTENT, WindowManager.LayoutParams.WRAP_CONTENT, type, WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL, PixelFormat.TRANSLUCENT).apply { gravity = Gravity.CENTER }
        
        windowManager.addView(layout, params)
        panelView = layout
    }

    private fun hidePanel() {
        if (panelView != null) { windowManager.removeView(panelView); panelView = null }
    }

    private fun buildNotification(): Notification {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel("sys_ch", "Sistem", NotificationManager.IMPORTANCE_MIN)
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
        return NotificationCompat.Builder(this, "sys_ch").setContentTitle("Sistem").setContentText("Berjalan").setSmallIcon(android.R.drawable.ic_menu_compass).build()
    }

    override fun onDestroy() {
        super.onDestroy()
        if (bubbleView != null) windowManager.removeView(bubbleView)
        if (panelView != null) windowManager.removeView(panelView)
    }
}
EOF

# 7. Bikin Gradle Wrapper & Workflow
cat << 'EOF' > .github/workflows/build.yml
name: Build APK
on: [push, workflow_dispatch]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
    - name: Checkout code
      uses: actions/checkout@v4
    - name: set up JDK 17
      uses: actions/setup-java@v4
      with:
        java-version: '17'
        distribution: 'temurin'
    - name: Build with Gradle
      run: |
        chmod +x setup.sh
        ./setup.sh
        gradle wrapper
        ./gradlew assembleDebug
    - name: Upload APK
      uses: actions/upload-artifact@v4
      with:
        name: StealthOverlay-APK
        path: app/build/outputs/apk/debug/app-debug.apk
EOF
