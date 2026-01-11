package com.monadial.ash.domain.services

import kotlinx.coroutines.flow.Flow

/**
 * Location result with latitude and longitude.
 * Precision is limited to 6 decimal places (~10cm) as per security spec.
 */
data class LocationResult(
    val latitude: Double,
    val longitude: Double
) {
    val formattedLatitude: String get() = "%.6f".format(latitude)
    val formattedLongitude: String get() = "%.6f".format(longitude)
}

/**
 * Location-specific errors.
 */
sealed class LocationError : Exception() {
    data object PermissionDenied : LocationError()
    data object Unavailable : LocationError()
    data object Timeout : LocationError()
}

/**
 * Service interface for device location access.
 *
 * Abstracts platform-specific location APIs for testability.
 */
interface LocationService {
    /**
     * Whether the app has fine location permission.
     */
    val hasLocationPermission: Boolean

    /**
     * Whether the app has coarse location permission.
     */
    val hasCoarseLocationPermission: Boolean

    /**
     * Get the current device location.
     *
     * @return Result containing location or error
     */
    suspend fun getCurrentLocation(): Result<LocationResult>

    /**
     * Observe continuous location updates.
     *
     * @return Flow of location updates
     */
    fun observeLocationUpdates(): Flow<LocationResult>
}
