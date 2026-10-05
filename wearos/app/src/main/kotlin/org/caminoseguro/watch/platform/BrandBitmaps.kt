package org.caminoseguro.watch.platform

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.provider.Settings

/** Decodificación del recurso de marca (§K.1) y preferencia de reducción de movimiento (§K.3). */
object BrandBitmaps {
    /** Lado máximo decodificado para la bienvenida (la imagen ocupa ~60 % de la pantalla). */
    private const val TARGET_SIDE_PX = 512

    private fun sampleSize(bytes: ByteArray): Int? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        val side = maxOf(bounds.outWidth, bounds.outHeight)
        if (side <= 0) return null
        var sample = 1
        while (side / (sample * 2) >= TARGET_SIDE_PX) sample *= 2
        return sample
    }

    /** Null si la plataforma no puede decodificarla. Llamar fuera del hilo principal. */
    fun decode(bytes: ByteArray): Bitmap? = try {
        sampleSize(bytes)?.let { sample ->
            BitmapFactory.decodeByteArray(bytes, 0, bytes.size, BitmapFactory.Options().apply { inSampleSize = sample })
        }
    } catch (e: RuntimeException) {
        null
    } catch (e: OutOfMemoryError) {
        null
    }

    /** Comprobación «la plataforma debe poder decodificarla» antes de aceptar una descarga. */
    fun canDecode(bytes: ByteArray): Boolean = decode(bytes)?.let { it.recycle(); true } ?: false

    /**
     * Reducción de movimiento: escala de animaciones a 0 (Opciones de desarrollo o «Quitar
     * animaciones» de Accesibilidad, que pone las escalas a 0).
     */
    fun reducedMotion(context: Context): Boolean {
        if (!ValueAnimator.areAnimatorsEnabled()) return true
        val scale = try {
            Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f)
        } catch (e: RuntimeException) {
            1f
        }
        return scale == 0f
    }
}
