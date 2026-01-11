@file:OptIn(androidx.camera.core.ExperimentalGetImage::class)

package com.monadial.ash.ui.components

import android.Manifest
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.util.Size
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.Preview
import androidx.camera.core.resolutionselector.ResolutionSelector
import androidx.camera.core.resolutionselector.ResolutionStrategy
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.google.accompanist.permissions.ExperimentalPermissionsApi
import com.google.accompanist.permissions.isGranted
import com.google.accompanist.permissions.rememberPermissionState
import com.google.mlkit.vision.barcode.BarcodeScannerOptions
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.common.InputImage
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicLong
import java.util.concurrent.atomic.AtomicReference

private const val TAG = "QRScanner"
private const val DEDUPLICATION_INTERVAL_MS = 300L

/**
 * Thread-safe callback holder that can be updated without recreating camera
 */
private class CallbackHolder(initialCallback: (String) -> Unit) {
    private val callbackRef = AtomicReference(initialCallback)
    private val lastScanTime = AtomicLong(0L)
    private val recentScans = ConcurrentHashMap<String, Long>()
    private val mainHandler = Handler(Looper.getMainLooper())

    fun updateCallback(callback: (String) -> Unit) {
        callbackRef.set(callback)
    }

    fun onQRScanned(value: String) {
        val now = System.currentTimeMillis()

        // Thread-safe deduplication
        val lastTime = recentScans[value]
        if (lastTime != null && (now - lastTime) < DEDUPLICATION_INTERVAL_MS) {
            return
        }

        // Update scan time
        recentScans[value] = now
        lastScanTime.set(now)

        // Clean old entries periodically
        if (recentScans.size > 100) {
            val cutoff = now - 5000 // Keep last 5 seconds
            recentScans.entries.removeIf { it.value < cutoff }
        }

        Log.d(TAG, "QR scanned: ${value.take(50)}...")

        // Always invoke callback on main thread
        mainHandler.post {
            callbackRef.get()?.invoke(value)
        }
    }
}

/**
 * QR Scanner View - stable camera implementation
 */
@OptIn(ExperimentalPermissionsApi::class)
@Composable
fun QRScannerView(onQRCodeScanned: (String) -> Unit, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val cameraPermissionState = rememberPermissionState(Manifest.permission.CAMERA)

    // Create stable callback holder that survives recomposition
    val callbackHolder = remember { CallbackHolder(onQRCodeScanned) }

    // Update callback reference when it changes (without recreating holder)
    LaunchedEffect(onQRCodeScanned) {
        callbackHolder.updateCallback(onQRCodeScanned)
    }

    LaunchedEffect(Unit) {
        if (!cameraPermissionState.status.isGranted) {
            cameraPermissionState.launchPermissionRequest()
        }
    }

    if (cameraPermissionState.status.isGranted) {
        var cameraProvider by remember { mutableStateOf<ProcessCameraProvider?>(null) }
        val analysisExecutor = remember { Executors.newSingleThreadExecutor() }

        DisposableEffect(Unit) {
            onDispose {
                Log.d(TAG, "Disposing QRScannerView - unbinding camera")
                cameraProvider?.unbindAll()
                analysisExecutor.shutdown()
            }
        }

        Box(
            modifier =
            modifier
                .fillMaxSize()
                .clip(RoundedCornerShape(16.dp))
                .background(Color.Black)
        ) {
            AndroidView(
                factory = { ctx ->
                    Log.d(TAG, "Creating PreviewView")
                    val previewView =
                        PreviewView(ctx).apply {
                            implementationMode = PreviewView.ImplementationMode.PERFORMANCE
                        }

                    setupCamera(
                        context = ctx,
                        lifecycleOwner = lifecycleOwner,
                        previewView = previewView,
                        analysisExecutor = analysisExecutor,
                        onCameraProviderReady = { provider -> cameraProvider = provider },
                        callbackHolder = callbackHolder
                    )

                    previewView
                },
                modifier = Modifier.fillMaxSize(),
                update = { /* no-op */ }
            )
        }
    } else {
        Box(
            modifier =
            modifier
                .fillMaxSize()
                .background(MaterialTheme.colorScheme.surfaceVariant),
            contentAlignment = Alignment.Center
        ) {
            Text(
                text = "Camera permission required",
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

private fun setupCamera(
    context: android.content.Context,
    lifecycleOwner: LifecycleOwner,
    previewView: PreviewView,
    analysisExecutor: ExecutorService,
    onCameraProviderReady: (ProcessCameraProvider) -> Unit,
    callbackHolder: CallbackHolder
) {
    val cameraProviderFuture = ProcessCameraProvider.getInstance(context)

    cameraProviderFuture.addListener({
        val provider = cameraProviderFuture.get()
        onCameraProviderReady(provider)

        val preview =
            Preview.Builder().build().also {
                it.surfaceProvider = previewView.surfaceProvider
            }

        val options =
            BarcodeScannerOptions.Builder()
                .setBarcodeFormats(Barcode.FORMAT_QR_CODE)
                .build()
        val barcodeScanner = BarcodeScanning.getClient(options)

        val resolutionSelector =
            ResolutionSelector.Builder()
                .setResolutionStrategy(
                    ResolutionStrategy(
                        Size(1920, 1080),
                        ResolutionStrategy.FALLBACK_RULE_CLOSEST_HIGHER_THEN_LOWER
                    )
                )
                .build()

        val imageAnalysis =
            ImageAnalysis.Builder()
                .setResolutionSelector(resolutionSelector)
                .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                .build()
                .also { analysis ->
                    analysis.setAnalyzer(analysisExecutor) { imageProxy ->
                        val mediaImage = imageProxy.image
                        if (mediaImage != null) {
                            val image =
                                InputImage.fromMediaImage(
                                    mediaImage,
                                    imageProxy.imageInfo.rotationDegrees
                                )

                            barcodeScanner.process(image)
                                .addOnSuccessListener { barcodes ->
                                    for (barcode in barcodes) {
                                        if (barcode.format == Barcode.FORMAT_QR_CODE) {
                                            barcode.rawValue?.let { value ->
                                                callbackHolder.onQRScanned(value)
                                            }
                                        }
                                    }
                                }
                                .addOnFailureListener { e ->
                                    Log.e(TAG, "Barcode scanning failed: ${e.message}")
                                }
                                .addOnCompleteListener {
                                    imageProxy.close()
                                }
                        } else {
                            imageProxy.close()
                        }
                    }
                }

        try {
            provider.unbindAll()
            provider.bindToLifecycle(
                lifecycleOwner,
                CameraSelector.DEFAULT_BACK_CAMERA,
                preview,
                imageAnalysis
            )
            Log.d(TAG, "Camera bound successfully")
        } catch (e: Exception) {
            Log.e(TAG, "Camera binding failed", e)
        }
    }, ContextCompat.getMainExecutor(context))
}

@Composable
fun ScanProgressOverlay(receivedBlocks: Int, totalBlocks: Int, modifier: Modifier = Modifier) {
    Box(
        modifier =
        modifier
            .clip(RoundedCornerShape(8.dp))
            .background(Color.Black.copy(alpha = 0.7f))
            .padding(horizontal = 24.dp, vertical = 16.dp)
    ) {
        Text(
            text = if (totalBlocks > 0) "$receivedBlocks / $totalBlocks blocks" else "Waiting for first frame...",
            style = MaterialTheme.typography.labelLarge,
            color = Color.White
        )
    }
}
