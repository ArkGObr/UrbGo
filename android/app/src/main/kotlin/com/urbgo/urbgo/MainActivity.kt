package com.urbgo.urbgo

import android.location.Address
import android.location.Geocoder
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Locale
import kotlin.concurrent.thread

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.urbgo.app/geocoder"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
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
    }
}
