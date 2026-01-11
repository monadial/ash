package com.monadial.ash.data.services

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.os.Looper
import androidx.core.content.ContextCompat
import com.google.android.gms.location.FusedLocationProviderClient
import com.google.android.gms.location.LocationCallback
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import com.monadial.ash.domain.services.LocationError
import com.monadial.ash.domain.services.LocationResult
import com.monadial.ash.domain.services.LocationService
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.suspendCancellableCoroutine

/**
 * Android implementation of LocationService using Google Play Services.
 */
@Singleton
class LocationServiceImpl @Inject constructor(
    @ApplicationContext private val context: Context
) : LocationService {

    private val fusedLocationClient: FusedLocationProviderClient =
        LocationServices.getFusedLocationProviderClient(context)

    override val hasLocationPermission: Boolean
        get() = ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.ACCESS_FINE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED

    override val hasCoarseLocationPermission: Boolean
        get() = ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.ACCESS_COARSE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED

    override suspend fun getCurrentLocation(): Result<LocationResult> {
        if (!hasLocationPermission && !hasCoarseLocationPermission) {
            return Result.failure(LocationError.PermissionDenied)
        }

        return try {
            val location = getLastKnownLocation() ?: requestFreshLocation()
            if (location != null) {
                Result.success(
                    LocationResult(
                        latitude = location.latitude,
                        longitude = location.longitude
                    )
                )
            } else {
                Result.failure(LocationError.Unavailable)
            }
        } catch (e: SecurityException) {
            Result.failure(LocationError.PermissionDenied)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    override fun observeLocationUpdates(): Flow<LocationResult> = callbackFlow {
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
                        LocationResult(
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

    private suspend fun getLastKnownLocation(): Location? = suspendCancellableCoroutine { continuation ->
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

    private suspend fun requestFreshLocation(): Location? = suspendCancellableCoroutine { continuation ->
        val locationRequest = LocationRequest.Builder(
            Priority.PRIORITY_HIGH_ACCURACY,
            1000L
        )
            .setMaxUpdates(1)
            .setWaitForAccurateLocation(true)
            .build()

        val callback = object : LocationCallback() {
            override fun onLocationResult(result: com.google.android.gms.location.LocationResult) {
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
}
