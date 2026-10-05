package org.caminoseguro.watch

import org.caminoseguro.watch.core.BlockedCaminoApi
import org.caminoseguro.watch.core.CaminoApi

/**
 * Release: contrato backend BLOQUEADO (contracts/README.md). Nunca se envía nada a ningún
 * servidor; los eventos quedan en la cola local. Cuando exista el contrato se añadirá aquí un
 * adaptador HTTP real sin tocar el dominio.
 */
object ApiModule {
    fun create(): CaminoApi = BlockedCaminoApi()
}
