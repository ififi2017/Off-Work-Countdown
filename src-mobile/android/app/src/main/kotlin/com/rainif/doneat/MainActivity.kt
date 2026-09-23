package com.rainif.doneat

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.lifecycle.lifecycleScope
import com.rainif.doneat.core.designsystem.DoneAtTheme
import com.rainif.doneat.core.domain.BackupSchema
import com.rainif.doneat.reminders.Reminders
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {
    override fun onStart() {
        super.onStart()
        // Revoking the exact-alarm grant sends no broadcast; re-check it whenever the app comes back.
        lifecycleScope.launch(Dispatchers.IO) { Reminders.sync(applicationContext).revalidate(System.currentTimeMillis()) }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            DoneAtTheme {
                Surface(Modifier.fillMaxSize()) {
                    // T03 probe screen only; real navigation arrives with T15.
                    Box(contentAlignment = Alignment.Center) {
                        Text("DoneAt · backup v${BackupSchema.EXPORT_VERSION}", style = MaterialTheme.typography.titleMedium)
                    }
                }
            }
        }
    }
}
