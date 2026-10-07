package com.ridego.rider

import android.location.Geocoder
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

class MainActivity : FlutterActivity() {
    private val locationChannel = "com.ridego.rider/location"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            locationChannel
        ).setMethodCallHandler { call, result ->
            if (call.method != "reverseGeocode") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            val latitude = call.argument<Double>("latitude")
            val longitude = call.argument<Double>("longitude")
            if (latitude == null || longitude == null) {
                result.error("INVALID_COORDINATES", "Latitude and longitude are required.", null)
                return@setMethodCallHandler
            }

            Thread {
                try {
                    val geocoder = Geocoder(this, Locale.getDefault())
                    @Suppress("DEPRECATION")
                    val addresses = geocoder.getFromLocation(latitude, longitude, 1)
                    val address = addresses?.firstOrNull()
                    val readable = address?.getAddressLine(0)
                        ?: listOfNotNull(
                            address?.subLocality,
                            address?.locality,
                            address?.adminArea,
                            address?.postalCode
                        ).distinct().joinToString(", ")

                    runOnUiThread {
                        result.success(readable.takeIf { it.isNotBlank() })
                    }
                } catch (error: Exception) {
                    runOnUiThread {
                        result.error("GEOCODER_FAILED", error.message, null)
                    }
                }
            }.start()
        }
    }
}
