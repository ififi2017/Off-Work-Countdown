package com.rainif.doneat.plus
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.rainif.doneat.DoneAtApplication
import com.rainif.doneat.core.designsystem.DoneAtTheme
/** Explicit debug-only entry to the real CN page, without skipping verification or granting Plus. */
class CnMembershipDebugActivity : ComponentActivity() {
 override fun onCreate(savedInstanceState: Bundle?) {
  super.onCreate(savedInstanceState); enableEdgeToEdge()
  val graph = (application as DoneAtApplication).graph
  setContent { DoneAtTheme { CnMembershipScreen(graph, { finish() }, null, {}) } }
 }
}
