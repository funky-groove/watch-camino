package org.caminoseguro.watch

import org.caminoseguro.watch.core.CaminoApi
import org.caminoseguro.watch.core.MockCaminoApi

/** Debug: adaptador simulado. La UI muestra la marca DEMO (spec §0). */
object ApiModule {
    fun create(): CaminoApi = MockCaminoApi(latencyMillis = 600)
}
