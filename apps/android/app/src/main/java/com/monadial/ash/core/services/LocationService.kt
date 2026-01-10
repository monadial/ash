package com.monadial.ash.core.services

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.os.Looper
import androidx.core.content.ContextCompat
import com.google.android.gms.location.FusedLocationProviderClient
import com.google.android.gms.location.LocationCallback
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationResult
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.suspendCancellableCoroutine
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

data class AshLocationResult(
    val latitude: Double,
    val longitude: Double
) {
    // Format to 6 decimal places (~10cm precision as per spec)
    val formattedLatitude: String get() = "%.6f".format(latitude)
    val formattedLongitude: String get() = "%.6f".format(longitude)
}

sealed class LocationError : Exception() {
    data object PermissionDenied : LocationError()
    data object LocationUnavailable : LocationError()
    data object Timeout : LocationError()
}

@Singleton
class LocationService @Inject constructor(
    @ApplicationContext private val context: Context
) {
    private val fusedLocationClient: FusedLocationProviderClient =
        LocationServices.getFusedLocationProviderClient(context)

    val hasLocationPermission: Boolean
        get() = ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.ACCESS_FINE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED

    val hasCoarseLocationPermission: Boolean
        get() = ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.ACCESS_COARSE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED

    suspend fun getCurrentLocation(): Result<AshLocationResult> {
        if (!hasLocationPermission && !hasCoarseLocationPermission) {
            return Result.failure(LocationError.PermissionDenied)
        }

        return try {
            val location = getLastKnownLocation() ?: requestFreshLocation()
            if (location != null) {
                Result.success(
                    AshLocationResult(
                        latitude = location.latitude,
                        longitude = location.longitude
                    )
                )
            } else {
                Result.failure(LocationError.LocationUnavailable)
            }
        } catch (e: SecurityException) {
            Result.failure(LocationError.PermissionDenied)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    private suspend fun getLastKnownLocation(): Location? =
        suspendCancellableCoroutine { continuation ->
            try {
                fusedLocationClient.lastLocation
                    .addOnSuccessListener { location ->
                        continuation.resume(location)
                    }
                    .addOnFailureListener { e ->
                        continuation.resumeWithException(e)
                    }
            } catch (e: SecurityException) {
                continuation.resumeWithException(e)
            }
        }

    private suspend fun requestFreshLocation(): Location? =
        suspendCancellableCoroutine { continuation ->
            val locationRequest = LocationRequest.Builder(
                Priority.PRIORITY_HIGH_ACCURACY,
                1000L
            )
                .setMaxUpdates(1)
                .setWaitForAccurateLocation(true)
                .build()

            val callback = object : LocationCallback() {
                override fun onLocationResult(result: LocationResult) {
                    fusedLocationClient.removeLocationUpdates(this)
                    continuation.resume(result.lastLocation)
                }
            }

            try {
                fusedLocationClient.requestLocationUpdates(
                    locationRequest,
                    callback,
                    Looper.getMainLooper()
                )

                continuation.invokeOnCancellation {
                    fusedLocationClient.removeLocationUpdates(callback)
                }
            } catch (e: SecurityException) {
                continuation.resumeWithException(e)
            }
        }

    fun observeLocationUpdates(): Flow<AshLocationResult> = callbackFlow {
        if (!hasLocationPermission && !hasCoarseLocationPermission) {
            close(LocationError.PermissionDenied)
            return@callbackFlow
        }

        val locationRequest = LocationRequest.Builder(
            Priority.PRIORITY_HIGH_ACCURACY,
            10000L
        ).build()

        val callback = object : LocationCallback() {
            override fun onLocationResult(result: com.google.android.gms.location.LocationResult) {
                result.lastLocation?.let { location ->
                    trySend(
                        AshLocationResult(
                            latitude = location.latitude,
                            longitude = location.longitude
                        )
                    )
                }
            }
        }

        try {
            fusedLocationClient.requestLocationUpdates(
                locationRequest,
                callback,
                Looper.getMainLooper()
            )
        } catch (e: SecurityException) {
            close(e)
        }

        awaitClose {
            fusedLocationClient.removeLocationUpdates(callback)
        }
    }
}
