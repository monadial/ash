package com.monadial.ash.ui.components

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.unit.dp

/**
 * Entropy collection canvas - just the drawing surface
 * Text/labels are handled by the parent EntropyCollectionContent
 */
@Composable
fun EntropyCollectionView(
    progress: Float,
    onPointCollected: (Float, Float) -> Unit,
    accentColor: Color = MaterialTheme.colorScheme.primary,
    modifier: Modifier = Modifier
) {
    val touchPoints = remember { mutableStateListOf<Offset>() }

    Box(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(MaterialTheme.colorScheme.surfaceVariant)
            .pointerInput(Unit) {
                detectDragGestures { change, _ ->
                    val point = change.position
                    touchPoints.add(point)
                    if (touchPoints.size > 1000) {
                        repeat(200) { touchPoints.removeFirstOrNull() }
                    }
                    // Normalize coordinates to 0-1 range
                    val normalizedX = point.x / size.width
                    val normalizedY = point.y / size.height
                    onPointCollected(normalizedX, normalizedY)
                }
            },
        contentAlignment = Alignment.Center
    ) {
        if (touchPoints.isEmpty()) {
            Text(
                text = "Touch and drag here",
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }

        Canvas(modifier = Modifier.fillMaxSize()) {
            if (touchPoints.size > 1) {
                val path = Path().apply {
                    moveTo(touchPoints[0].x, touchPoints[0].y)
                    touchPoints.drop(1).forEach { point ->
                        lineTo(point.x, point.y)
                    }
                }
                drawPath(
                    path = path,
                    color = accentColor.copy(alpha = 0.7f),
                    style = Stroke(
                        width = 4.dp.toPx(),
                        cap = StrokeCap.Round,
                        join = StrokeJoin.Round
                    )
                )
            }
        }
    }
}
