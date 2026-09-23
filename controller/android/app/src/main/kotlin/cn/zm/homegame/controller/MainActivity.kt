package cn.zm.homegame.controller

import android.annotation.SuppressLint
import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.SystemClock
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {

    companion object {
        private const val UDP_CHANNEL = "cn.zm.homegame/udp"
        private const val SENSOR_CHANNEL = "cn.zm.homegame/sensor"
    }

    private var udpChannel: MethodChannel? = null
    private var sensorEventChannel: EventChannel? = null

    // UDP socket。由 open() 创建、close() 释放。
    @Volatile private var socket: DatagramSocket? = null

    // 60Hz 高频 send，用一个单线程池串行化发送，避免多线程抢 socket。
    private val sendExecutor = Executors.newSingleThreadExecutor()

    // 传感器相关。
    private var sensorManager: SensorManager? = null
    private var sensorListener: SensorEventListener? = null
    private var accelSensor: Sensor? = null
    private var gyroSensor: Sensor? = null
    private var sensorSink: EventChannel.EventSink? = null

    // 两个传感器回调频率不同，各自更新各自的分量，在发事件时组合成完整一帧。
    private val latest = FloatArray(6) // [ax, ay, az, gx, gy, gz]
    @Volatile private var haveAccel = false
    @Volatile private var haveGyro = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        udpChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, UDP_CHANNEL)
        udpChannel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "open" -> open(call, result)
                "send" -> send(call, result)
                "close" -> close(result)
                else -> result.notImplemented()
            }
        }

        sensorEventChannel =
            EventChannel(flutterEngine.dartExecutor.binaryMessenger, SENSOR_CHANNEL)
        sensorEventChannel!!.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                sensorSink = events
                startSensors()
            }

            override fun onCancel(arguments: Any?) {
                stopSensors()
                sensorSink = null
            }
        })
    }

    // ---- UDP ----

    private fun open(call: MethodChannel.MethodCall, result: MethodChannel.Result) {
        val port = call.argument<Int>("port") ?: 0
        try {
            val s = DatagramSocket(port)
            socket = s
            result.success(mapOf("ok" to true, "error" to null))
        } catch (e: Exception) {
            socket = null
            result.success(mapOf("ok" to false, "error" to (e.message ?: e.toString())))
        }
    }

    // send 必须在后台线程做（DatagramSocket.send 可能阻塞），结果回主线程。
    private fun send(call: MethodChannel.MethodCall, result: MethodChannel.Result) {
        val host = call.argument<String>("host")
        val port = call.argument<Int>("port")
        val bytes = call.argument<ByteArray>("bytes")
        if (host == null || port == null || bytes == null) {
            result.success(mapOf("ok" to false, "error" to "send 参数缺失 (host/port/bytes)"))
            return
        }
        sendExecutor.execute {
            val ok: Boolean
            val err: String?
            try {
                val s = socket
                if (s == null) {
                    ok = false
                    err = "socket 未打开，请先调用 open()"
                } else {
                    val packet = DatagramPacket(bytes, bytes.size, InetAddress.getByName(host), port)
                    s.send(packet)
                    ok = true
                    err = null
                }
            } catch (e: Exception) {
                ok = false
                err = e.message ?: e.toString()
            }
            // 回主线程把结果交给 Dart。
            runOnUiThread { result.success(mapOf("ok" to ok, "error" to err)) }
        }
    }

    private fun close(result: MethodChannel.Result) {
        try {
            socket?.close()
        } catch (_: Exception) {
            // 关不掉就算了
        }
        socket = null
        result.success(mapOf("ok" to true, "error" to null))
    }

    // ---- 传感器 ----

    @SuppressLint("MissingPermission") // 权限在 AndroidManifest 声明；上架前需接隐私弹窗。
    private fun startSensors() {
        // 上架前 TODO：此处应先确认用户已同意隐私政策，再开始读传感器。
        if (sensorManager == null) {
            sensorManager = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        }
        if (accelSensor == null) {
            accelSensor = sensorManager!!.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
        }
        if (gyroSensor == null) {
            gyroSensor = sensorManager!!.getDefaultSensor(Sensor.TYPE_GYROSCOPE)
        }
        if (sensorListener == null) {
            sensorListener = object : SensorEventListener {
                override fun onSensorChanged(event: SensorEvent) {
                    when (event.sensor.type) {
                        Sensor.TYPE_ACCELEROMETER -> {
                            latest[0] = event.values[0]
                            latest[1] = event.values[1]
                            latest[2] = event.values[2]
                            haveAccel = true
                        }
                        Sensor.TYPE_GYROSCOPE -> {
                            latest[3] = event.values[0]
                            latest[4] = event.values[1]
                            latest[5] = event.values[2]
                            haveGyro = true
                        }
                    }
                    // 两个传感器都至少到过一次再往上推，避免前半段是 0 的脏数据。
                    if (haveAccel && haveGyro) {
                        val ts = SystemClock.elapsedRealtime()
                        sensorSink?.success(
                            mapOf(
                                "gx" to latest[3],
                                "gy" to latest[4],
                                "gz" to latest[5],
                                "ax" to latest[0],
                                "ay" to latest[1],
                                "az" to latest[2],
                                "ts" to ts,
                            )
                        )
                    }
                }

                override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {
                    // 不需要处理
                }
            }
        }
        // SENSOR_DELAY_GAME ≈ 游戏级采样率（约 10–60Hz，取决于硬件）。
        accelSensor?.let {
            sensorManager!!.registerListener(sensorListener, it, SensorManager.SENSOR_DELAY_GAME)
        }
        gyroSensor?.let {
            sensorManager!!.registerListener(sensorListener, it, SensorManager.SENSOR_DELAY_GAME)
        }
    }

    private fun stopSensors() {
        sensorListener?.let { sensorManager?.unregisterListener(it) }
    }

    override fun onDestroy() {
        super.onDestroy()
        stopSensors()
        try {
            socket?.close()
        } catch (_: Exception) {
        }
        socket = null
        sendExecutor.shutdown()
    }
}
