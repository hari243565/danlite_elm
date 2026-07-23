package com.danlite.elm

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothSocket
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.util.UUID

class BluetoothSppPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {

    companion object {
        private const val SPP_UUID        = "00001101-0000-1000-8000-00805F9B34FB"
        const val METHOD_CHANNEL          = "com.danlite.elm/bluetooth_classic"
        const val DATA_EVENT_CHANNEL      = "com.danlite.elm/bluetooth_data"
        const val DISCOVERY_EVENT_CHANNEL = "com.danlite.elm/bluetooth_discovery"
    }

    private lateinit var methodChannel: MethodChannel
    private lateinit var dataEventChannel: EventChannel
    private lateinit var discoveryEventChannel: EventChannel

    private var dataEventSink: EventChannel.EventSink? = null
    private var discoveryEventSink: EventChannel.EventSink? = null

    private var btAdapter: BluetoothAdapter? = null
    private var btSocket: BluetoothSocket? = null
    private var inputStream: InputStream? = null
    private var outputStream: OutputStream? = null
    private var context: Context? = null

    private val pluginScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var readJob: Job? = null

    private var bondCallback: ((String, Int) -> Unit)? = null

    private val broadcastReceiver = object : BroadcastReceiver() {
        override fun onReceive(ctx: Context, intent: Intent) {
            try {
                when (intent.action) {
                    BluetoothDevice.ACTION_FOUND -> {
                        val device: BluetoothDevice? = if (Build.VERSION.SDK_INT >= 33) {
                            intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE, BluetoothDevice::class.java)
                        } else {
                            @Suppress("DEPRECATION")
                            intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
                        }
                        device?.let { emitDiscoveredDevice(it) }
                    }
                    BluetoothAdapter.ACTION_DISCOVERY_FINISHED -> {
                        pluginScope.launch(Dispatchers.Main) {
                            try {
                                discoveryEventSink?.endOfStream()
                            } catch (_: Exception) {}
                            discoveryEventSink = null
                        }
                    }
                    BluetoothDevice.ACTION_BOND_STATE_CHANGED -> {
                        val device: BluetoothDevice? = if (Build.VERSION.SDK_INT >= 33) {
                            intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE, BluetoothDevice::class.java)
                        } else {
                            @Suppress("DEPRECATION")
                            intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
                        }
                        val state = intent.getIntExtra(
                            BluetoothDevice.EXTRA_BOND_STATE, BluetoothDevice.BOND_NONE)
                        bondCallback?.invoke(device?.address ?: "", state)
                    }
                }
            } catch (e: Exception) {
                // Never let a broadcast crash the plugin
            }
        }
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        val btManager = context?.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
        btAdapter = btManager?.adapter

        methodChannel = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL)
        methodChannel.setMethodCallHandler(this)

        dataEventChannel = EventChannel(binding.binaryMessenger, DATA_EVENT_CHANNEL)
        dataEventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(args: Any?, sink: EventChannel.EventSink?) { dataEventSink = sink }
            override fun onCancel(args: Any?) { dataEventSink = null }
        })

        discoveryEventChannel = EventChannel(binding.binaryMessenger, DISCOVERY_EVENT_CHANNEL)
        discoveryEventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(args: Any?, sink: EventChannel.EventSink?) { discoveryEventSink = sink }
            override fun onCancel(args: Any?) { discoveryEventSink = null }
        })

        registerReceiver()
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        try { context?.unregisterReceiver(broadcastReceiver) } catch (_: Exception) {}
        pluginScope.cancel()
        closeSocket()
    }

    private fun registerReceiver() {
        val filter = IntentFilter().apply {
            addAction(BluetoothDevice.ACTION_FOUND)
            addAction(BluetoothAdapter.ACTION_DISCOVERY_FINISHED)
            addAction(BluetoothDevice.ACTION_BOND_STATE_CHANGED)
        }
        try {
            if (Build.VERSION.SDK_INT >= 33) {
                context?.registerReceiver(broadcastReceiver, filter, Context.RECEIVER_EXPORTED)
            } else {
                context?.registerReceiver(broadcastReceiver, filter)
            }
        } catch (e: Exception) {
            // Already registered — safe to ignore
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isBluetoothEnabled" -> result.success(btAdapter?.isEnabled == true)
            "getBondedDevices"   -> getBondedDevices(result)
            "startDiscovery"     -> startDiscovery(result)
            "cancelDiscovery"    -> {
                try { btAdapter?.cancelDiscovery() } catch (_: Exception) {}
                result.success(true)
            }
            "bondDevice"         -> bondDevice(call.argument("address")!!, result)
            "connect"            -> connect(call.argument("address")!!, result)
            "disconnect"         -> { closeSocket(); result.success(true) }
            "write"              -> writeCommand(call.argument("data")!!, result)
            "isConnected"        -> result.success(btSocket?.isConnected == true)
            else                 -> result.notImplemented()
        }
    }

    private fun getBondedDevices(result: MethodChannel.Result) {
        try {
            val devices = btAdapter?.bondedDevices
                ?.map { deviceToMap(it, bonded = true) }
                ?: emptyList()
            result.success(devices)
        } catch (e: SecurityException) {
            result.error("PERMISSION", "Bluetooth permission denied", null)
        } catch (e: Exception) {
            result.error("UNKNOWN", e.message, null)
        }
    }

    private fun startDiscovery(result: MethodChannel.Result) {
        try {
            btAdapter?.cancelDiscovery()
            val started = btAdapter?.startDiscovery() == true
            result.success(started)
        } catch (e: SecurityException) {
            result.error("PERMISSION", "BLUETOOTH_SCAN permission denied", null)
        } catch (e: Exception) {
            result.error("UNKNOWN", e.message, null)
        }
    }

    private fun emitDiscoveredDevice(device: BluetoothDevice) {
        pluginScope.launch(Dispatchers.Main) {
            try {
                discoveryEventSink?.success(deviceToMap(device, bonded = false))
            } catch (_: Exception) {}
        }
    }

    private fun bondDevice(address: String, result: MethodChannel.Result) {
        val device = try {
            btAdapter?.getRemoteDevice(address)
        } catch (e: Exception) {
            result.error("INVALID_ADDRESS", "Invalid address: $address", null)
            return
        }

        if (device == null) {
            result.error("NO_DEVICE", "Device not found", null)
            return
        }

        if (device.bondState == BluetoothDevice.BOND_BONDED) {
            result.success(true)
            return
        }

        var responded = false

        bondCallback = { addr, state ->
            if (addr == address && !responded) {
                when (state) {
                    BluetoothDevice.BOND_BONDED -> {
                        responded = true
                        bondCallback = null
                        pluginScope.launch(Dispatchers.Main) { result.success(true) }
                    }
                    BluetoothDevice.BOND_NONE -> {
                        responded = true
                        bondCallback = null
                        pluginScope.launch(Dispatchers.Main) {
                            result.error("BOND_FAILED", "Bonding failed or rejected", null)
                        }
                    }
                }
            }
        }

        pluginScope.launch {
            delay(30_000)
            if (!responded) {
                responded = true
                bondCallback = null
                withContext(Dispatchers.Main) {
                    result.error("BOND_TIMEOUT", "Bonding timed out", null)
                }
            }
        }

        try {
            if (!device.createBond()) {
                responded = true
                bondCallback = null
                result.error("BOND_START_FAILED", "createBond() returned false", null)
            }
        } catch (e: SecurityException) {
            responded = true
            bondCallback = null
            result.error("PERMISSION", "BLUETOOTH_CONNECT permission denied", null)
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CONNECT — RFCOMM SPP
    // ═══════════════════════════════════════════════════════════════════════
    private fun connect(address: String, result: MethodChannel.Result) {
        pluginScope.launch {
            var resultSent = false

            fun sendError(code: String, msg: String) {
                if (!resultSent) {
                    resultSent = true
                    pluginScope.launch(Dispatchers.Main) { result.error(code, msg, null) }
                }
            }

            fun sendSuccess() {
                if (!resultSent) {
                    resultSent = true
                    pluginScope.launch(Dispatchers.Main) { result.success(true) }
                }
            }

            closeSocket()

            val device = try {
                btAdapter?.getRemoteDevice(address)
            } catch (e: Exception) {
                sendError("INVALID_ADDRESS", "Invalid address: $address")
                return@launch
            }

            if (device == null) {
                sendError("NO_DEVICE", "Device not found for address: $address")
                return@launch
            }

            try { btAdapter?.cancelDiscovery() } catch (_: Exception) {}

            val sppUuid = UUID.fromString(SPP_UUID)
            val socket = createSocket(device, sppUuid) ?: run {
                sendError("SOCKET_CREATE_FAILED", "Could not create RFCOMM socket")
                return@launch
            }

            btSocket = socket

            val connected = tryConnect(socket, device)
            if (!connected) {
                closeSocket()
                sendError("CONNECT_FAILED", "RFCOMM connection refused by device")
                return@launch
            }

            try {
                inputStream  = btSocket?.inputStream
                outputStream = btSocket?.outputStream
            } catch (e: IOException) {
                closeSocket()
                sendError("STREAM_FAILED", "Could not open I/O streams: ${e.message}")
                return@launch
            }

            startReadLoop()
            sendSuccess()
        }
    }

    private fun createSocket(device: BluetoothDevice, uuid: UUID): BluetoothSocket? {
        return try {
            device.createRfcommSocketToServiceRecord(uuid)
        } catch (e1: Exception) {
            try {
                device.createInsecureRfcommSocketToServiceRecord(uuid)
            } catch (e2: Exception) {
                null
            }
        }
    }

    private fun tryConnect(socket: BluetoothSocket, device: BluetoothDevice): Boolean {
        return try {
            socket.connect()
            true
        } catch (e: IOException) {
            try {
                socket.close()
                val clazz = device.javaClass
                val createRfcommMethod = clazz.getMethod("createRfcommSocket", Int::class.java)
                val fallbackSocket = createRfcommMethod.invoke(device, 1) as BluetoothSocket
                btSocket = fallbackSocket
                fallbackSocket.connect()
                true
            } catch (e2: Exception) {
                false
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // READ LOOP — CRITICAL FIX: emit RAW chunks, do NOT strip '>'.
    // Dart owns terminator parsing (single source of truth for framing).
    // This mirrors the WiFi socket path exactly, so both transports behave
    // identically from Dart's perspective.
    // ═══════════════════════════════════════════════════════════════════════
    private fun startReadLoop() {
        readJob?.cancel()
        readJob = pluginScope.launch {
            val buffer = ByteArray(1024)

            while (isActive) {
                val sock = btSocket
                if (sock == null || !sock.isConnected) break

                try {
                    val bytes = inputStream?.read(buffer) ?: -1
                    if (bytes == -1) {
                        // Stream closed by remote device
                        withContext(Dispatchers.Main) {
                            dataEventSink?.error("STREAM_CLOSED", "Remote closed connection", null)
                        }
                        break
                    }
                    if (bytes > 0) {
                        // Emit the RAW chunk exactly as received — including any '>'.
                        // Never filter, never strip here. Dart is the single
                        // source of truth for buffering/terminator detection.
                        val chunk = String(buffer, 0, bytes, Charsets.ISO_8859_1)
                        if (chunk.isNotEmpty()) {
                            withContext(Dispatchers.Main) {
                                try {
                                    dataEventSink?.success(chunk)
                                } catch (_: Exception) {}
                            }
                        }
                    }
                } catch (e: IOException) {
                    withContext(Dispatchers.Main) {
                        try {
                            dataEventSink?.error("READ_ERROR", e.message, null)
                        } catch (_: Exception) {}
                    }
                    break
                } catch (e: Exception) {
                    // Never let a stray exception kill the read loop silently
                    // without informing Dart.
                    withContext(Dispatchers.Main) {
                        try {
                            dataEventSink?.error("READ_UNKNOWN", e.message, null)
                        } catch (_: Exception) {}
                    }
                    break
                }
            }
        }
    }

    private fun writeCommand(data: String, result: MethodChannel.Result) {
        pluginScope.launch {
            try {
                val out = outputStream
                if (out == null) {
                    withContext(Dispatchers.Main) {
                        result.error("NOT_CONNECTED", "Output stream is null", null)
                    }
                    return@launch
                }
                out.write("$data\r".toByteArray(Charsets.ISO_8859_1))
                out.flush()
                withContext(Dispatchers.Main) { result.success(true) }
            } catch (e: IOException) {
                withContext(Dispatchers.Main) {
                    result.error("WRITE_ERROR", e.message, null)
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    result.error("WRITE_UNKNOWN", e.message, null)
                }
            }
        }
    }

    private fun closeSocket() {
        readJob?.cancel(); readJob = null
        try { inputStream?.close()  } catch (_: Exception) {}
        try { outputStream?.close() } catch (_: Exception) {}
        try { btSocket?.close()     } catch (_: Exception) {}
        inputStream = null; outputStream = null; btSocket = null
    }

    private fun deviceToMap(device: BluetoothDevice, bonded: Boolean): Map<String, Any> = try {
        mapOf(
            "name"    to (device.name ?: "Unknown"),
            "address" to device.address,
            "bonded"  to bonded,
        )
    } catch (_: SecurityException) {
        mapOf("name" to "Unknown", "address" to device.address, "bonded" to bonded)
    }
}