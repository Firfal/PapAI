package com.quentin.papai.aidant

import android.Manifest
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts

class MainActivity : ComponentActivity() {
    private val askNotif = registerForActivityResult(ActivityResultContracts.RequestPermission()) {}

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        enableEdgeToEdge()
        if (Build.VERSION.SDK_INT >= 33) askNotif.launch(Manifest.permission.POST_NOTIFICATIONS)
        setContent { Root() }
    }

    override fun onResume() {
        super.onResume()
        Helper.foreground = true
        // Relit aussi la configuration gérée : l'administrateur a pu la pousser entre-temps.
        Helper.wakeUp()
        if (Helper.isConfigured) LinkService.start(this)
    }

    override fun onPause() {
        super.onPause()
        Helper.foreground = false
    }
}
