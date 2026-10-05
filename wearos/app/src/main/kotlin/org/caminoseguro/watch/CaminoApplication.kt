package org.caminoseguro.watch

import android.app.Application
import org.caminoseguro.watch.platform.Notifications

class CaminoApplication : Application() {

    lateinit var container: AppContainer
        private set

    override fun onCreate() {
        super.onCreate()
        Notifications.createChannels(this)
        container = AppContainer(this)
        container.boot()
    }
}
