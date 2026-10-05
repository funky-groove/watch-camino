package org.caminoseguro.watch.ui

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.viewModels
import org.caminoseguro.watch.CaminoApplication

class MainActivity : ComponentActivity() {

    private val viewModel: CaminoViewModel by viewModels(
        factoryProducer = { CaminoViewModel.Factory(application as CaminoApplication) },
    )

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent { CaminoApp(viewModel) }
    }

    override fun onStart() {
        super.onStart()
        viewModel.onForeground()
    }

    override fun onStop() {
        viewModel.onBackground()
        super.onStop()
    }
}
