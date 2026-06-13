package com.arkgo.arkgo

import android.app.Activity
import android.content.Intent
import android.location.Address
import android.location.Geocoder
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.Locale
import kotlin.concurrent.thread

class MainActivity : FlutterActivity() {
    private val geocoderChannel = "com.arkgo.app/geocoder"
    private val documentPickerChannel = "com.arkgo.app/document_picker"
    private val documentOpenerChannel = "com.arkgo.app/document_opener"
    private val pickPdfRequestCode = 9001
    private var pendingPdfResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, geocoderChannel).setMethodCallHandler { call, result ->
            if (call.method == "geocode") {
                val query = call.argument<String>("query")
                val focusLat = call.argument<Double>("focusLat")
                val focusLng = call.argument<Double>("focusLng")

                if (query == null) {
                    result.error("INVALID_ARGUMENT", "Query missing", null)
                    return@setMethodCallHandler
                }

                thread {
                    try {
                        val geocoder = Geocoder(context, Locale.forLanguageTag("pt-BR"))
                        val addresses: List<Address>? = if (focusLat != null && focusLng != null) {
                            // Cria bounding box de ~50km para priorizar buscas locais
                            val lowerLeftLat = focusLat - 0.5
                            val lowerLeftLng = focusLng - 0.5
                            val upperRightLat = focusLat + 0.5
                            val upperRightLng = focusLng + 0.5
                            geocoder.getFromLocationName(query, 6, lowerLeftLat, lowerLeftLng, upperRightLat, upperRightLng)
                        } else {
                            geocoder.getFromLocationName(query, 6)
                        }

                        val response = addresses?.map { addr ->
                            val sb = StringBuilder()
                            for (i in 0..addr.maxAddressLineIndex) {
                                sb.append(addr.getAddressLine(i)).append(", ")
                            }
                            var label = sb.toString().trimEnd(',', ' ')
                            if (label.isEmpty()) {
                                label = addr.featureName ?: "Endereço"
                            }

                            mapOf(
                                "label" to label,
                                "lat" to addr.latitude,
                                "lng" to addr.longitude
                            )
                        } ?: emptyList()

                        Handler(Looper.getMainLooper()).post {
                            result.success(response)
                        }
                    } catch (e: Exception) {
                        Handler(Looper.getMainLooper()).post {
                            result.error("GEOCODER_ERROR", e.message, null)
                        }
                    }
                }
            } else if (call.method == "reverseGeocode") {
                val lat = call.argument<Double>("lat")
                val lng = call.argument<Double>("lng")

                if (lat == null || lng == null) {
                    result.error("INVALID_ARGUMENT", "Lat/Lng missing", null)
                    return@setMethodCallHandler
                }

                thread {
                    try {
                        val geocoder = Geocoder(context, Locale.forLanguageTag("pt-BR"))
                        val addresses = geocoder.getFromLocation(lat, lng, 1)

                        if (addresses.isNullOrEmpty()) {
                            Handler(Looper.getMainLooper()).post { result.success(null) }
                        } else {
                            val addr = addresses[0]
                            val sb = StringBuilder()
                            for (i in 0..addr.maxAddressLineIndex) {
                                sb.append(addr.getAddressLine(i)).append(", ")
                            }
                            val label = sb.toString().trimEnd(',', ' ')

                            Handler(Looper.getMainLooper()).post { result.success(label) }
                        }
                    } catch (e: Exception) {
                        Handler(Looper.getMainLooper()).post { result.error("GEOCODER_ERROR", e.message, null) }
                    }
                }
            } else {
                result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, documentPickerChannel).setMethodCallHandler { call, result ->
            if (call.method == "pickPdf") {
                if (pendingPdfResult != null) {
                    result.error("PICK_IN_PROGRESS", "Já existe uma seleção de PDF em andamento.", null)
                    return@setMethodCallHandler
                }

                pendingPdfResult = result
                val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = "application/pdf"
                }

                try {
                    startActivityForResult(intent, pickPdfRequestCode)
                } catch (e: Exception) {
                    pendingPdfResult = null
                    result.error("PICK_FAILED", e.message, null)
                }
            } else {
                result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, documentOpenerChannel).setMethodCallHandler { call, result ->
            if (call.method == "openDocument") {
                val path = call.argument<String>("path")
                val mimeType = call.argument<String>("mimeType") ?: "*/*"

                if (path.isNullOrBlank()) {
                    result.error("INVALID_ARGUMENT", "Path missing", null)
                    return@setMethodCallHandler
                }

                try {
                    openDocument(path, mimeType)
                    result.success(null)
                } catch (e: Exception) {
                    result.error("OPEN_DOCUMENT_FAILED", e.message, null)
                }
            } else {
                result.notImplemented()
            }
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)

        if (requestCode != pickPdfRequestCode) return

        val result = pendingPdfResult
        pendingPdfResult = null

        if (resultCode != Activity.RESULT_OK) {
            result?.success(null)
            return
        }

        val uri = data?.data
        if (uri == null) {
            result?.error("PICK_FAILED", "Nenhum arquivo selecionado.", null)
            return
        }

        try {
            val filePath = copyUriToCache(uri)
            result?.success(filePath)
        } catch (e: Exception) {
            result?.error("PICK_FAILED", e.message, null)
        }
    }

    private fun copyUriToCache(uri: Uri): String {
        val resolver = applicationContext.contentResolver
        val fileName = queryDisplayName(uri) ?: "documento-${System.currentTimeMillis()}.pdf"
        val safeName = if (fileName.endsWith(".pdf", ignoreCase = true)) fileName else "$fileName.pdf"
        val outputFile = File(cacheDir, safeName)

        resolver.openInputStream(uri)?.use { input ->
            outputFile.outputStream().use { output ->
                input.copyTo(output)
            }
        } ?: throw IllegalStateException("Não foi possível ler o PDF selecionado.")

        return outputFile.absolutePath
    }

    private fun queryDisplayName(uri: Uri): String? {
        val resolver = applicationContext.contentResolver
        resolver.query(uri, null, null, null, null)?.use { cursor ->
            val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            if (nameIndex >= 0 && cursor.moveToFirst()) {
                return cursor.getString(nameIndex)
            }
        }
        return null
    }

    private fun openDocument(path: String, mimeType: String) {
        val file = File(path)
        if (!file.exists()) {
            throw IllegalStateException("Arquivo não encontrado para abertura.")
        }

        val uri = FileProvider.getUriForFile(
            this,
            "${applicationContext.packageName}.fileprovider",
            file
        )

        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, mimeType)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }

        startActivity(Intent.createChooser(intent, "Abrir documento"))
    }
}
