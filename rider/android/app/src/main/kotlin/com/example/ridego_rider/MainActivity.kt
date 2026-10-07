package com.ridego.rider

import android.content.pm.PackageManager
import android.location.Geocoder
import com.google.android.libraries.places.api.Places
import com.google.android.libraries.places.api.model.AutocompleteSessionToken
import com.google.android.libraries.places.api.model.Place
import com.google.android.libraries.places.api.net.FetchPlaceRequest
import com.google.android.libraries.places.api.net.FindAutocompletePredictionsRequest
import com.google.android.libraries.places.api.net.PlacesClient
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

class MainActivity : FlutterActivity() {
    private val locationChannel = "com.ridego.rider/location"
    private var placesClient: PlacesClient? = null
    private var autocompleteSessionToken: AutocompleteSessionToken? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            locationChannel
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "reverseGeocode" -> reverseGeocode(
                    call.argument<Double>("latitude"),
                    call.argument<Double>("longitude"),
                    result
                )
                "searchPlaces" -> searchPlaces(
                    call.argument<String>("query"),
                    result
                )
                "placeDetails" -> placeDetails(
                    call.argument<String>("placeId"),
                    result
                )
                else -> result.notImplemented()
            }
        }
    }

    private fun ensurePlacesClient(): PlacesClient {
        placesClient?.let { return it }
        val appInfo = packageManager.getApplicationInfo(
            packageName,
            PackageManager.GET_META_DATA
        )
        val apiKey = appInfo.metaData?.getString("com.google.android.geo.API_KEY").orEmpty()
        if (apiKey.isBlank()) throw IllegalStateException("Google Maps API key is not configured")
        if (!Places.isInitialized()) {
            Places.initializeWithNewPlacesApiEnabled(applicationContext, apiKey)
        }
        return Places.createClient(this).also { placesClient = it }
    }

    private fun searchPlaces(query: String?, result: MethodChannel.Result) {
        val text = query?.trim().orEmpty()
        if (text.length < 2) {
            result.success(emptyList<Map<String, String>>())
            return
        }
        try {
            val client = ensurePlacesClient()
            val token = autocompleteSessionToken
                ?: AutocompleteSessionToken.newInstance().also { autocompleteSessionToken = it }
            val request = FindAutocompletePredictionsRequest.builder()
                .setQuery(text)
                .setCountries("IN")
                .setRegionCode("IN")
                .setSessionToken(token)
                .build()

            client.findAutocompletePredictions(request)
                .addOnSuccessListener { response ->
                    val predictions = response.autocompletePredictions.map {
                        mapOf(
                            "placeId" to it.placeId,
                            "label" to it.getFullText(null).toString()
                        )
                    }
                    result.success(predictions)
                }
                .addOnFailureListener { error ->
                    result.error("PLACES_SEARCH_FAILED", error.message ?: "Places search failed", null)
                }
        } catch (error: Exception) {
            result.error("PLACES_INIT_FAILED", error.message ?: "Places initialization failed", null)
        }
    }

    private fun placeDetails(placeId: String?, result: MethodChannel.Result) {
        val id = placeId?.trim().orEmpty()
        if (id.isEmpty()) {
            result.error("INVALID_PLACE", "Place ID is required", null)
            return
        }
        try {
            val client = ensurePlacesClient()
            val fields = listOf(Place.Field.LAT_LNG, Place.Field.ADDRESS, Place.Field.NAME)
            val builder = FetchPlaceRequest.builder(id, fields)
            autocompleteSessionToken?.let { builder.setSessionToken(it) }

            client.fetchPlace(builder.build())
                .addOnSuccessListener { response ->
                    autocompleteSessionToken = null
                    val place = response.place
                    val latLng = place.latLng
                    if (latLng == null) {
                        result.error("PLACE_LOCATION_MISSING", "Destination coordinates were not returned", null)
                    } else {
                        result.success(
                            mapOf(
                                "latitude" to latLng.latitude,
                                "longitude" to latLng.longitude,
                                "address" to (place.address ?: place.name ?: "")
                            )
                        )
                    }
                }
                .addOnFailureListener { error ->
                    autocompleteSessionToken = null
                    result.error("PLACE_DETAILS_FAILED", error.message ?: "Place details failed", null)
                }
        } catch (error: Exception) {
            autocompleteSessionToken = null
            result.error("PLACES_INIT_FAILED", error.message ?: "Places initialization failed", null)
        }
    }

    private fun reverseGeocode(
        latitude: Double?,
        longitude: Double?,
        result: MethodChannel.Result
    ) {
        if (latitude == null || longitude == null) {
            result.error("INVALID_COORDINATES", "Latitude and longitude are required.", null)
            return
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
