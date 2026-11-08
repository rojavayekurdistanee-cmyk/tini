package com.aras.titistar

import kotlin.math.*

/** Normalized, top-down detector coordinates. No Android dependencies. */
internal data class TiniRetouchRegion(
    val left: Float,
    val top: Float,
    val right: Float,
    val bottom: Float,
    val mouthLeft: Float,
    val mouthTop: Float,
    val mouthRight: Float,
    val mouthBottom: Float,
)

/**
 * Tracks landmarks between detector results, rather than displaying a stale mask. All work uses a
 * bounded, small grayscale image from the existing GPU decoder. A delayed detector result is
 * replayed through the frame history before use.
 */
internal class TiniRetouchMotion {
    internal data class Warp(
        val region: TiniRetouchRegion,
        val face: FloatArray,
        val mouth: FloatArray,
        val teethConfidence: Float,
    )

    private data class Level(val w: Int, val h: Int, val gray: FloatArray) {
        fun at(x: Float, y: Float): Float {
            val ix = x.toInt().coerceIn(0, w - 2)
            val iy = y.toInt().coerceIn(0, h - 2)
            val fx = (x - ix).coerceIn(0f, 1f)
            val fy = (y - iy).coerceIn(0f, 1f)
            return (gray[iy * w + ix] * (1 - fx) + gray[iy * w + ix + 1] * fx) * (1 - fy) +
                (gray[(iy + 1) * w + ix] * (1 - fx) + gray[(iy + 1) * w + ix + 1] * fx) * fy
        }
    }

    private data class Frame(val id: Long, val w: Int, val h: Int, val gray: ByteArray) {
        val pyramid: List<Level> by lazy {
            val levels =
                mutableListOf(
                    Level(w, h, FloatArray(gray.size) { (gray[it].toInt() and 255).toFloat() })
                )
            while (levels.size < 4 && min(levels.last().w, levels.last().h) >= 28) {
                val p = levels.last()
                val nw = p.w / 2
                val nh = p.h / 2
                val data = FloatArray(nw * nh)
                for (y in 0 until nh) for (x in 0 until nw) {
                    val i = y * 2 * p.w + x * 2
                    data[y * nw + x] =
                        (p.gray[i] + p.gray[i + 1] + p.gray[i + p.w] + p.gray[i + p.w + 1]) * .25f
                }
                levels.add(Level(nw, nh, data))
            }
            levels
        }
    }

    private data class Point(val ox: Float, val oy: Float, var x: Float = ox, var y: Float = oy)

    private data class Track(
        val region: TiniRetouchRegion,
        var face: MutableList<Point>,
        var mouth: MutableList<Point>,
        var faceWarp: DoubleArray? = doubleArrayOf(1.0, 0.0, 0.0, 0.0, 1.0, 0.0),
        var mouthWarp: DoubleArray? = doubleArrayOf(1.0, 0.0, 0.0, 0.0, 1.0, 0.0),
    )

    private val history = ArrayDeque<Frame>()
    private var tracks = emptyList<Track>()
    private var width = 0
    private var height = 0
    val frameId: Long
        get() = history.lastOrNull()?.id ?: -1

    val hasAnchor: Boolean
        get() = tracks.isNotEmpty()

    fun reset() {
        history.clear()
        tracks = emptyList()
        width = 0
        height = 0
    }

    /** [gray] is owned by the caller; history keeps its own immutable copy. */
    fun push(id: Long, w: Int, h: Int, gray: ByteArray) {
        require(w >= 12 && h >= 12 && gray.size == w * h)
        if (width != w || height != h) reset()
        width = w
        height = h
        val next = Frame(id, w, h, gray.copyOf())
        history.lastOrNull()?.let { previous -> advance(previous, next) }
        history.addLast(next)
        while (history.size > 40) history.removeFirst()
    }

    /** Reject results older than retained history; never attach them to a new frame. */
    fun anchor(id: Long, regions: List<TiniRetouchRegion>): Boolean {
        val frames = history.toList()
        val index = frames.indexOfFirst { it.id == id }
        if (index < 0) return false
        val start = frames[index]
        tracks =
            regions.map { r ->
                val mx = (r.mouthLeft + r.mouthRight) * .5f
                val my = (r.mouthTop + r.mouthBottom) * .5f
                val mw = max(r.mouthRight - r.mouthLeft, (r.right - r.left) * .25f)
                val mh = max((r.mouthBottom - r.mouthTop) * 1.4f, (r.bottom - r.top) * .12f)
                Track(
                    r,
                    features(start, r.left, r.top, r.right, r.bottom, 36),
                    features(start, mx - mw * .6f, my - mh * .6f, mx + mw * .6f, my + mh * .6f, 24),
                )
            }
        for (i in index + 1 until frames.size) advance(frames[i - 1], frames[i])
        return true
    }

    private fun features(
        frame: Frame,
        left: Float,
        top: Float,
        right: Float,
        bottom: Float,
        count: Int,
    ): MutableList<Point> {
        val image = frame.pyramid[0]
        val candidates = mutableListOf<Pair<Float, Point>>()
        val x0 = max(4, (left * width).toInt())
        val y0 = max(4, (top * height).toInt())
        val x1 = min(width - 5, (right * width).toInt())
        val y1 = min(height - 5, (bottom * height).toInt())
        for (y in y0..y1 step 2) for (x in x0..x1 step 2) {
            var xx = 0f
            var xy = 0f
            var yy = 0f
            for (dy in -2..2) for (dx in -2..2) {
                val i = (y + dy) * width + x + dx
                val gx = (image.gray[i + 1] - image.gray[i - 1]) * .5f
                val gy = (image.gray[i + width] - image.gray[i - width]) * .5f
                xx += gx * gx
                xy += gx * gy
                yy += gy * gy
            }
            val quality = (xx + yy - sqrt((xx - yy) * (xx - yy) + 4 * xy * xy)) * .5f
            if (quality > 30f) candidates.add(quality to Point(x.toFloat(), y.toFloat()))
        }
        val chosen = mutableListOf<Point>()
        for ((_, p) in candidates.sortedByDescending { it.first }) {
            if (chosen.none { (it.x - p.x).pow(2) + (it.y - p.y).pow(2) < 16f }) chosen.add(p)
            if (chosen.size >= count) break
        }
        return chosen
    }

    private fun advance(previous: Frame, next: Frame) {
        for (track in tracks) {
            track.face = follow(previous, next, track.face)
            track.mouth = follow(previous, next, track.mouth)
            val face = fit(track.face)
            val mouth = fit(track.mouth)
            val unchanged =
                if (face == null || mouth == null) unchanged(previous, next, track.region)
                else false
            track.faceWarp = face ?: if (unchanged) track.faceWarp else null
            track.mouthWarp = mouth ?: if (unchanged) track.mouthWarp else null
        }
    }

    // A freshly detected, stationary face must not lose its mask just because
    // overexposed skin has too few corners for optical flow. Never use this
    // fallback across a change of image/scene.
    private fun unchanged(a: Frame, b: Frame, r: TiniRetouchRegion): Boolean {
        var total = 0L
        var count = 0
        var largest = 0
        val x0 = (r.left * width).toInt().coerceIn(0, width - 1)
        val x1 = (r.right * width).toInt().coerceIn(0, width - 1)
        val y0 = (r.top * height).toInt().coerceIn(0, height - 1)
        val y1 = (r.bottom * height).toInt().coerceIn(0, height - 1)
        for (y in y0..y1 step 3) for (x in x0..x1 step 3) {
            val index = y * width + x
            val delta = abs((a.gray[index].toInt() and 255) - (b.gray[index].toInt() and 255))
            total += delta
            count++
            largest = max(largest, delta)
        }
        return count > 0 && total.toDouble() / count < 1.5 && largest < 12
    }

    private fun follow(a: Frame, b: Frame, points: List<Point>): MutableList<Point> {
        val valid = mutableListOf<Point>()
        for (p in points) {
            val q = lk(a.pyramid, b.pyramid, p.x, p.y, p.x, p.y) ?: continue
            val back = lk(b.pyramid, a.pyramid, q.first, q.second, p.x, p.y) ?: continue
            if (hypot(back.first - p.x, back.second - p.y) > 1f) continue
            valid.add(Point(p.ox, p.oy, q.first, q.second))
        }
        return valid
    }

    private fun lk(
        a: List<Level>,
        b: List<Level>,
        px: Float,
        py: Float,
        guessX: Float,
        guessY: Float,
    ): Pair<Float, Float>? {
        val top = min(a.size, b.size) - 1
        var qx = guessX / (1 shl top)
        var qy = guessY / (1 shl top)
        for (level in top downTo 0) {
            if (level < top) {
                qx *= 2
                qy *= 2
            }
            val old = a[level]
            val now = b[level]
            val scale = (1 shl level).toFloat()
            val x = px / scale
            val y = py / scale
            if (x < 4 || y < 4 || x > old.w - 5 || y > old.h - 5) continue
            val values = FloatArray(25)
            val gx = FloatArray(25)
            val gy = FloatArray(25)
            var xx = 0f
            var xy = 0f
            var yy = 0f
            var k = 0
            for (dy in -2..2) for (dx in -2..2) {
                values[k] = old.at(x + dx, y + dy)
                gx[k] = (old.at(x + dx + 1, y + dy) - old.at(x + dx - 1, y + dy)) * .5f
                gy[k] = (old.at(x + dx, y + dy + 1) - old.at(x + dx, y + dy - 1)) * .5f
                xx += gx[k] * gx[k]
                xy += gx[k] * gy[k]
                yy += gy[k] * gy[k]
                k++
            }
            val det = xx * yy - xy * xy
            if (det < 1f) {
                if (level == 0) return null else continue
            }
            for (iteration in 0 until 12) {
                if (qx < 3 || qy < 3 || qx > now.w - 4 || qy > now.h - 4) return null
                var bx = 0f
                var by = 0f
                k = 0
                for (dy in -2..2) for (dx in -2..2) {
                    val error = values[k] - now.at(qx + dx, qy + dy)
                    bx += gx[k] * error
                    by += gy[k] * error
                    k++
                }
                val sx = ((yy * bx - xy * by) / det).coerceIn(-2f, 2f)
                val sy = ((xx * by - xy * bx) / det).coerceIn(-2f, 2f)
                qx += sx
                qy += sy
                if (sx * sx + sy * sy < .0004f) break
            }
            if (level == 0) {
                var residual = 0f
                k = 0
                for (dy in -2..2) for (dx in -2..2) residual +=
                    abs(values[k++] - now.at(qx + dx, qy + dy))
                if (residual / 25 > 28f) return null
            }
        }
        return qx to qy
    }

    fun warps(): List<Warp> =
        tracks.mapNotNull { track ->
            val face = track.faceWarp ?: return@mapNotNull null
            val mouth = track.mouthWarp
            Warp(
                track.region,
                inverseNormalized(face),
                inverseNormalized(mouth ?: face),
                if (mouth != null) 1f else .85f,
            )
        }

    /** Robust affine fit. Feature outliers cannot drag the mouth to a cheek. */
    private fun fit(points: List<Point>): DoubleArray? {
        if (points.size < 3) return null
        val random = java.util.Random(73)
        var best = emptyList<Point>()
        for (attempt in 0 until min(48, points.size * 3)) {
            val selected =
                if (attempt == 0) points
                else {
                    val ids = mutableSetOf<Int>()
                    while (ids.size < 3) ids.add(random.nextInt(points.size))
                    ids.map { points[it] }
                }
            val model = solve(selected) ?: continue
            if (!reasonable(model)) continue
            val inliers =
                points.filter { p ->
                    hypot(
                        model[0] * p.ox + model[1] * p.oy + model[2] - p.x,
                        model[3] * p.ox + model[4] * p.oy + model[5] - p.y,
                    ) < 1.15
                }
            if (inliers.size > best.size) best = inliers
            if (best.size == points.size) break
        }
        if (best.size < 3 || best.size * 2 < points.size) return null
        return solve(best)?.takeIf(::reasonable)
    }

    private fun reasonable(m: DoubleArray): Boolean {
        val det = m[0] * m[4] - m[1] * m[3]
        return m.all { it.isFinite() } &&
            det in .35..2.8 &&
            hypot(m[0], m[3]) in .5..1.8 &&
            hypot(m[1], m[4]) in .5..1.8
    }

    private fun solve(points: List<Point>): DoubleArray? {
        val a = Array(3) { DoubleArray(5) }
        for (p in points) {
            val v = doubleArrayOf(p.ox.toDouble(), p.oy.toDouble(), 1.0)
            for (i in 0..2) {
                for (j in 0..2) a[i][j] += v[i] * v[j]
                a[i][3] += v[i] * p.x
                a[i][4] += v[i] * p.y
            }
        }
        for (col in 0..2) {
            val pivot = (col..2).maxBy { abs(a[it][col]) }
            if (abs(a[pivot][col]) < 1e-6) return null
            val row = a[col]
            a[col] = a[pivot]
            a[pivot] = row
            val d = a[col][col]
            for (j in col..4) a[col][j] /= d
            for (i in 0..2) if (i != col) {
                val factor = a[i][col]
                for (j in col..4) a[i][j] -= factor * a[col][j]
            }
        }
        return doubleArrayOf(a[0][3], a[1][3], a[2][3], a[0][4], a[1][4], a[2][4])
    }

    private fun inverseNormalized(m: DoubleArray): FloatArray {
        val det = m[0] * m[4] - m[1] * m[3]
        val a = m[4] / det
        val b = -m[1] / det
        val d = -m[3] / det
        val e = m[0] / det
        val c = -(a * m[2] + b * m[5])
        val f = -(d * m[2] + e * m[5])
        return floatArrayOf(
            a.toFloat(),
            (d * width / height).toFloat(),
            0f,
            (b * height / width).toFloat(),
            e.toFloat(),
            0f,
            (c / width).toFloat(),
            (f / height).toFloat(),
            1f,
        )
    }
}
