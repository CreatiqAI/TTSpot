package my.ttspot.app

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Rect
import android.media.ExifInterface
import android.os.Handler
import android.os.Looper
import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.common.GoogleApiAvailability
import com.google.android.gms.common.moduleinstall.ModuleInstall
import com.google.android.gms.common.moduleinstall.ModuleInstallRequest
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.common.MlKitException
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.segmentation.subject.Subject
import com.google.mlkit.vision.segmentation.subject.SubjectSegmentation
import com.google.mlkit.vision.segmentation.subject.SubjectSegmenter
import com.google.mlkit.vision.segmentation.subject.SubjectSegmenterOptions
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.util.concurrent.ExecutionException
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * Garage cut-outs: the car cut out of the member's own photo, on the phone.
 * ML Kit subject segmentation runs inside Google Play services (the model is
 * an optional module Play downloads on first use). Dart side:
 * lib/features/profile/data/car_cutout_channel.dart; iOS twin in AppDelegate.swift.
 *
 * "cutout" {bytes, maxSide} → {status, png?, areaRatio, edgeLeft/Right/Top/Bottom,
 * subjects, secondRatio, width, height}. Status: ok | no_subject | unsupported
 * (no Google Play) | not_ready (model still downloading) | error.
 */
object CarCutout {
    private const val MAX_INPUT = 1600
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    private val segmenter: SubjectSegmenter by lazy {
        SubjectSegmentation.getClient(
            SubjectSegmenterOptions.Builder()
                .enableMultipleSubjects(
                    SubjectSegmenterOptions.SubjectResultOptions.Builder()
                        .enableConfidenceMask()
                        .enableSubjectBitmap()
                        .build()
                )
                .build()
        )
    }

    fun register(messenger: BinaryMessenger, context: Context) {
        val app = context.applicationContext
        MethodChannel(messenger, "my.ttspot.app/cutout").setMethodCallHandler { call, result ->
            if (call.method != "cutout") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val bytes = call.argument<ByteArray>("bytes")
            val maxSide = call.argument<Int>("maxSide") ?: 1080
            if (bytes == null) {
                result.error("bad_args", "bytes are required", null)
                return@setMethodCallHandler
            }
            worker.execute {
                val out = try {
                    run(app, bytes, maxSide)
                } catch (e: OutOfMemoryError) {
                    mapOf("status" to "error", "message" to "out of memory")
                } catch (e: Exception) {
                    mapOf("status" to "error", "message" to (e.message ?: e.javaClass.simpleName))
                }
                main.post { result.success(out) }
            }
        }
    }

    /** Runs on [worker]; blocks on the Play services tasks. */
    private fun run(context: Context, bytes: ByteArray, maxSide: Int): Map<String, Any?> {
        if (GoogleApiAvailability.getInstance().isGooglePlayServicesAvailable(context) != ConnectionResult.SUCCESS) {
            return mapOf("status" to "unsupported", "message" to "Google Play services unavailable")
        }

        // The model is an optional Play module: ask for it the first time and come back later.
        val installer = ModuleInstall.getClient(context)
        val available = try {
            Tasks.await(installer.areModulesAvailable(segmenter), 20, TimeUnit.SECONDS).areModulesAvailable()
        } catch (e: Exception) {
            true // can't tell: try anyway, process() says so if it's missing
        }
        if (!available) {
            installer.installModules(ModuleInstallRequest.newBuilder().addApi(segmenter).build())
            return mapOf("status" to "not_ready", "message" to "downloading the model")
        }

        val photo = decode(bytes) ?: return mapOf("status" to "error", "message" to "can't read the photo")
        val result = try {
            Tasks.await(segmenter.process(InputImage.fromBitmap(photo, 0)), 60, TimeUnit.SECONDS)
        } catch (e: ExecutionException) {
            val cause = e.cause
            if (cause is MlKitException && cause.errorCode == MlKitException.UNAVAILABLE) {
                installer.installModules(ModuleInstallRequest.newBuilder().addApi(segmenter).build())
                return mapOf("status" to "not_ready", "message" to (cause.message ?: "model unavailable"))
            }
            throw e
        }

        val w = photo.width
        val h = photo.height
        val subjects = result.subjects.filter { it.width > 0 && it.height > 0 }
        if (subjects.isEmpty()) return mapOf("status" to "no_subject", "subjects" to 0)

        // Largest subject by mask area; the rest are ignored.
        val areas = subjects.map { maskArea(it) }
        val order = areas.indices.sortedByDescending { areas[it] }
        val mainIdx = order[0]
        val subject = subjects[mainIdx]
        val area = areas[mainIdx]
        if (area == 0) return mapOf("status" to "no_subject", "subjects" to 0)
        val second = if (order.size > 1) areas[order[1]] else 0

        val edges = edgeTouches(subject, w, h)
        val cut = subject.bitmap ?: return mapOf("status" to "error", "message" to "no subject bitmap")
        val png = encode(cut, maxSide)
        cut.recycle()
        photo.recycle()

        return mapOf(
            "status" to "ok",
            "png" to png,
            "areaRatio" to area.toDouble() / (w.toDouble() * h.toDouble()),
            "edgeLeft" to edges[0],
            "edgeRight" to edges[1],
            "edgeTop" to edges[2],
            "edgeBottom" to edges[3],
            "subjects" to subjects.size,
            "secondRatio" to second.toDouble() / area.toDouble(),
            "width" to subject.width,
            "height" to subject.height,
        )
    }

    private fun maskArea(s: Subject): Int {
        val mask = s.confidenceMask ?: return s.width * s.height
        mask.rewind()
        var n = 0
        while (mask.hasRemaining()) if (mask.get() > 0.5f) n++
        return n
    }

    /**
     * How much of each photo edge the subject runs into: the share of rows
     * (left/right) or columns (top/bottom) with a subject pixel within a thin
     * band (1 % of the side) along that edge. [left, right, top, bottom].
     */
    private fun edgeTouches(s: Subject, w: Int, h: Int): DoubleArray {
        val mask = s.confidenceMask ?: return doubleArrayOf(0.0, 0.0, 0.0, 0.0)
        val bandX = max(2, (w * 0.01).roundToInt())
        val bandY = max(2, (h * 0.01).roundToInt())
        val sx = s.startX
        val sy = s.startY
        val sw = s.width
        val sh = s.height
        fun on(x: Int, y: Int): Boolean = mask.get(y * sw + x) > 0.5f // subject-local

        var left = 0
        if (sx < bandX) {
            val cols = min(sw, bandX - sx)
            for (y in 0 until sh) { for (x in 0 until cols) if (on(x, y)) { left++; break } }
        }
        var right = 0
        if (sx + sw > w - bandX) {
            val from = max(0, (w - bandX) - sx)
            for (y in 0 until sh) { for (x in from until sw) if (on(x, y)) { right++; break } }
        }
        var top = 0
        if (sy < bandY) {
            val rows = min(sh, bandY - sy)
            for (x in 0 until sw) { for (y in 0 until rows) if (on(x, y)) { top++; break } }
        }
        var bottom = 0
        if (sy + sh > h - bandY) {
            val from = max(0, (h - bandY) - sy)
            for (x in 0 until sw) { for (y in from until sh) if (on(x, y)) { bottom++; break } }
        }
        return doubleArrayOf(left.toDouble() / h, right.toDouble() / h, top.toDouble() / w, bottom.toDouble() / w)
    }

    /** The photo upright, longest side at most [MAX_INPUT]. */
    private fun decode(bytes: ByteArray): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
        var sample = 1
        while (max(bounds.outWidth, bounds.outHeight) / (sample * 2) >= MAX_INPUT) sample *= 2
        val opts = BitmapFactory.Options().apply {
            inSampleSize = sample
            inPreferredConfig = Bitmap.Config.ARGB_8888
        }
        var bmp = BitmapFactory.decodeByteArray(bytes, 0, bytes.size, opts) ?: return null
        val longest = max(bmp.width, bmp.height)
        if (longest > MAX_INPUT) {
            val k = MAX_INPUT.toFloat() / longest
            val scaled = Bitmap.createScaledBitmap(bmp, (bmp.width * k).roundToInt(), (bmp.height * k).roundToInt(), true)
            if (scaled !== bmp) bmp.recycle()
            bmp = scaled
        }
        val degrees = try {
            when (ExifInterface(ByteArrayInputStream(bytes)).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)) {
                ExifInterface.ORIENTATION_ROTATE_90 -> 90f
                ExifInterface.ORIENTATION_ROTATE_180 -> 180f
                ExifInterface.ORIENTATION_ROTATE_270 -> 270f
                else -> 0f
            }
        } catch (e: Exception) {
            0f
        }
        if (degrees != 0f) {
            val rotated = Bitmap.createBitmap(bmp, 0, 0, bmp.width, bmp.height, Matrix().apply { postRotate(degrees) }, true)
            if (rotated !== bmp) bmp.recycle()
            bmp = rotated
        }
        return bmp
    }

    /**
     * A little transparent room left, right and above the car, none below (the
     * tyres sit on the PNG's bottom edge, so the bay can stand it on the floor
     * and hang the reflection straight under it). Longest side at most
     * [maxSide], as PNG.
     */
    private fun encode(cut: Bitmap, maxSide: Int): ByteArray {
        val pad = max(2, (max(cut.width, cut.height) * 0.03).roundToInt())
        val pw = cut.width + pad * 2
        val ph = cut.height + pad
        val k = min(1f, maxSide.toFloat() / max(pw, ph))
        val ow = max(1, (pw * k).roundToInt())
        val oh = max(1, (ph * k).roundToInt())
        val out = Bitmap.createBitmap(ow, oh, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(out)
        val dst = Rect((pad * k).roundToInt(), (pad * k).roundToInt(), ((pad + cut.width) * k).roundToInt(), ((pad + cut.height) * k).roundToInt())
        canvas.drawBitmap(cut, null, dst, Paint(Paint.FILTER_BITMAP_FLAG or Paint.ANTI_ALIAS_FLAG))
        val stream = ByteArrayOutputStream()
        out.compress(Bitmap.CompressFormat.PNG, 100, stream)
        out.recycle()
        return stream.toByteArray()
    }
}
