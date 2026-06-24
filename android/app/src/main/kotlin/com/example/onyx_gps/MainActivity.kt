package com.example.onyx_gps

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothSocket
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.location.LocationManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.InputStream
import java.io.OutputStream
import java.util.Locale
import java.util.UUID
import kotlin.concurrent.thread

class MainActivity : FlutterActivity() {
    private val channelName = "onyx_gps/obd_bluetooth"
    private val permissionRequestCode = 4227
    private val sppUuid: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")

    private var socket: BluetoothSocket? = null
    private var input: InputStream? = null
    private var output: OutputStream? = null
    private var scanReceiver: BroadcastReceiver? = null
    private var pairingReceiver: BroadcastReceiver? = null
    private var bleScanCallback: ScanCallback? = null
    private var scanResult: MethodChannel.Result? = null
    private var permissionResult: MethodChannel.Result? = null
    private val scanDevices = linkedMapOf<String, Map<String, Any?>>()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "canDrawOverlays" -> result.success(canDrawOverlays())
                    "requestOverlayPermission" -> requestOverlayPermission(result)
                    "startAssistantBubble" -> {
                        startAssistantBubble()
                        result.success(true)
                    }
                    "stopAssistantBubble" -> {
                        stopAssistantBubble()
                        result.success(true)
                                        }
                    "requestPermissions" -> requestBluetoothPermissions(result)
                    "requestVoicePermission" -> requestVoicePermission(result)
                    "bluetoothStatus" -> bluetoothStatus(result)
                    "requestEnableBluetooth" -> requestEnableBluetooth(result)
                    "listPairedDevices" -> listPairedDevices(result)
                    "scanDevices" -> {
                        val timeoutMs = call.argument<Int>("timeoutMs") ?: 12000
                        scanDevices(timeoutMs, result)
                    }
                    "connect" -> {
                        val address = call.argument<String>("address")
                        if (address.isNullOrBlank()) {
                            result.error("missing_address", "Endereco Bluetooth ausente", null)
                        } else {
                            connect(address, result)
                        }
                    }
                    "pairDevice" -> {
                        val address = call.argument<String>("address")
                        val pin = call.argument<String>("pin")?.trim()?.takeIf { it.isNotEmpty() }
                        if (address.isNullOrBlank()) {
                            result.error("missing_address", "Endereco Bluetooth ausente", null)
                        } else {
                            pairDevice(address, pin, result)
                        }
                    }
                    "forgetDevice" -> {
                        val address = call.argument<String>("address")
                        if (address.isNullOrBlank()) {
                            result.error("missing_address", "Endereco Bluetooth ausente", null)
                        } else {
                            forgetDevice(address, result)
                        }
                    }
                    "sendCommand" -> {
                        val command = call.argument<String>("command")
                        val timeoutMs = call.argument<Int>("timeoutMs") ?: 3000
                        if (command.isNullOrBlank()) {
                            result.error("missing_command", "Comando ausente", null)
                        } else {
                            sendCommand(command, timeoutMs, result)
                        }
                    }
                    "disconnect" -> {
                        disconnect()
                        result.success(true)
                    }
                    "cancelScan" -> {
                        finishScan()
                        result.success(true)
                    }
                    "isConnected" -> result.success(input != null && output != null)
                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        finishScan()
        unregisterPairingReceiver(pairingReceiver)
        disconnect()
        permissionResult = null
        super.onDestroy()
    }

    private fun canDrawOverlays(): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.canDrawOverlays(this)
    }

    private fun requestOverlayPermission(result: MethodChannel.Result) {
        if (canDrawOverlays()) {
            result.success(true)
            return
        }
        try {
            val intent = Intent(
                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                Uri.parse("package:$packageName"),
            )
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
            result.success(false)
        } catch (error: Throwable) {
            result.error("overlay_failed", error.message ?: "Falha ao abrir permissão de sobreposição", null)
        }
    }

    private fun startAssistantBubble() {
        if (!canDrawOverlays()) return
        val intent = Intent(this, AssistantBubbleService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    private fun stopAssistantBubble() {
        stopService(Intent(this, AssistantBubbleService::class.java))
    }
    private fun requestVoicePermission(result: MethodChannel.Result) {
        if (permissionResult != null) {
            result.error("permission_busy", "Solicitacao de permissao ja em andamento", null)
            return
        }
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
            result.success(true)
            return
        }

        permissionResult = result
        requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), permissionRequestCode)
    }

    private fun requestBluetoothPermissions(result: MethodChannel.Result) {
        if (permissionResult != null) {
            result.error("permission_busy", "Solicitacao de permissao ja em andamento", null)
            return
        }
        val permissions = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            arrayOf(
                Manifest.permission.BLUETOOTH_CONNECT,
                Manifest.permission.BLUETOOTH_SCAN,
                Manifest.permission.BLUETOOTH_ADVERTISE,
                Manifest.permission.ACCESS_FINE_LOCATION,
            )
        } else {
            arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)
        }
        val missing = permissions.filter {
            checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED
        }
        if (missing.isEmpty()) {
            result.success(true)
            return
        }

        permissionResult = result
        requestPermissions(missing.toTypedArray(), permissionRequestCode)
    }

    private fun bluetoothStatus(result: MethodChannel.Result) {
        val adapter = bluetoothAdapter()
        val bondedCount = try {
            adapter?.bondedDevices?.size ?: 0
        } catch (_: Throwable) {
            0
        }
        result.success(
            mapOf(
                "sdk" to Build.VERSION.SDK_INT,
                "available" to (adapter != null),
                "enabled" to (adapter?.isEnabled == true),
                "permissionsGranted" to (hasBluetoothPermission() && hasScanPermission()),
                "connectPermission" to hasBluetoothPermission(),
                "scanPermission" to hasScanPermission(),
                "locationPermission" to (
                    checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED ||
                        checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED
                    ),
                "locationEnabled" to isLocationEnabledForScan(),
                "discovering" to (adapter?.isDiscovering == true),
                "bondedCount" to bondedCount,
                "connected" to (socket?.isConnected == true),
            ),
        )
    }

    private fun requestEnableBluetooth(result: MethodChannel.Result) {
        val adapter = bluetoothAdapter()
        if (adapter == null) {
            result.error("bluetooth_unavailable", "Bluetooth indisponivel", null)
            return
        }
        if (adapter.isEnabled) {
            result.success(true)
            return
        }
        try {
            val intent = Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE)
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
            result.success(false)
        } catch (error: Throwable) {
            result.error("enable_failed", error.message ?: "Falha ao abrir solicitacao Bluetooth", null)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != permissionRequestCode) return
        val result = permissionResult ?: return
        permissionResult = null
        result.success(grantResults.isNotEmpty() && grantResults.all {
            it == PackageManager.PERMISSION_GRANTED
        })
    }

    private fun scanDevices(timeoutMs: Int, result: MethodChannel.Result) {
        if (!hasBluetoothPermission() || !hasScanPermission()) {
            result.error("permission_denied", "Permissao Bluetooth/Localizacao nao concedida", null)
            return
        }

        val adapter = bluetoothAdapter()
        if (adapter == null) {
            result.error("bluetooth_unavailable", "Bluetooth indisponivel", null)
            return
        }
        if (!adapter.isEnabled) {
            result.error("bluetooth_disabled", "Bluetooth desligado", null)
            return
        }
        if (!isLocationEnabledForScan()) {
            result.error(
                "location_disabled",
                "Ative a Localizacao do Android para descobrir novos dispositivos Bluetooth",
                null,
            )
            return
        }
        if (scanResult != null) {
            result.error("scan_busy", "Busca Bluetooth ja em andamento", null)
            return
        }

        scanDevices.clear()
        adapter.bondedDevices.forEach { device ->
            scanDevices[device.address] = deviceMap(device, true)
        }
        scanResult = result

        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                when (intent.action) {
                    BluetoothDevice.ACTION_FOUND -> {
                        val device = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            intent.getParcelableExtra(
                                BluetoothDevice.EXTRA_DEVICE,
                                BluetoothDevice::class.java,
                            )
                        } else {
                            @Suppress("DEPRECATION")
                            intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
                        }
                        if (device != null && device.address != null) {
                            val rssi = intent.getShortExtra(BluetoothDevice.EXTRA_RSSI, Short.MIN_VALUE)
                            scanDevices[device.address] = deviceMap(
                                device,
                                device.bondState == BluetoothDevice.BOND_BONDED,
                                rssi = if (rssi == Short.MIN_VALUE) null else rssi.toInt(),
                            )
                        }
                    }
                    BluetoothDevice.ACTION_NAME_CHANGED,
                    BluetoothDevice.ACTION_BOND_STATE_CHANGED -> {
                        val device = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            intent.getParcelableExtra(
                                BluetoothDevice.EXTRA_DEVICE,
                                BluetoothDevice::class.java,
                            )
                        } else {
                            @Suppress("DEPRECATION")
                            intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
                        }
                        if (device != null && device.address != null) {
                            scanDevices[device.address] = deviceMap(device, device.bondState == BluetoothDevice.BOND_BONDED)
                        }
                    }
                    BluetoothAdapter.ACTION_DISCOVERY_FINISHED -> finishScan()
                }
            }
        }

        scanReceiver = receiver
        val filter = IntentFilter().apply {
            addAction(BluetoothDevice.ACTION_FOUND)
            addAction(BluetoothDevice.ACTION_NAME_CHANGED)
            addAction(BluetoothDevice.ACTION_BOND_STATE_CHANGED)
            addAction(BluetoothAdapter.ACTION_DISCOVERY_FINISHED)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(receiver, filter)
        }

        if (adapter.isDiscovering) adapter.cancelDiscovery()
        val classicStarted = try {
            adapter.startDiscovery()
        } catch (_: Throwable) {
            false
        }
        val bleStarted = startBleScan(adapter)
        if (!classicStarted && !bleStarted) {
            finishScanWithError(
                "scan_failed",
                "Nao foi possivel iniciar busca Bluetooth classica nem BLE",
            )
            return
        }

        Handler(Looper.getMainLooper()).postDelayed({
            finishScan()
        }, timeoutMs.coerceIn(4000, 20000).toLong())
    }

    private fun startBleScan(adapter: BluetoothAdapter): Boolean {
        val scanner = try {
            adapter.bluetoothLeScanner
        } catch (_: Throwable) {
            null
        } ?: return false

        val callback = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, result: ScanResult) {
                val device = result.device ?: return
                if (device.address != null) {
                    scanDevices[device.address] = deviceMap(
                        device,
                        device.bondState == BluetoothDevice.BOND_BONDED,
                        "BLE",
                        result.rssi,
                    )
                }
            }

            override fun onBatchScanResults(results: MutableList<ScanResult>) {
                results.forEach { onScanResult(ScanSettings.CALLBACK_TYPE_ALL_MATCHES, it) }
            }
        }

        return try {
            val settings = ScanSettings.Builder()
                .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
                .build()
            bleScanCallback = callback
            scanner.startScan(null, settings, callback)
            true
        } catch (_: Throwable) {
            bleScanCallback = null
            false
        }
    }

    private fun listPairedDevices(result: MethodChannel.Result) {
        if (!hasBluetoothPermission()) {
            result.error("permission_denied", "Permissao Bluetooth nao concedida", null)
            return
        }

        val adapter = bluetoothAdapter()
        if (adapter == null) {
            result.error("bluetooth_unavailable", "Bluetooth indisponivel", null)
            return
        }
        if (!adapter.isEnabled) {
            result.error("bluetooth_disabled", "Bluetooth desligado", null)
            return
        }

        val devices = adapter.bondedDevices.map { device ->
            deviceMap(device, true)
        }.sortedWith(compareByDescending<Map<String, Any?>> {
            it["elmCandidate"] == true
        }.thenBy {
            (it["name"] as? String)?.lowercase(Locale.US) ?: ""
        })

        result.success(devices)
    }

    private fun connect(address: String, result: MethodChannel.Result) {
        if (!hasBluetoothPermission()) {
            result.error("permission_denied", "Permissao Bluetooth nao concedida", null)
            return
        }

        thread {
            try {
                disconnect()
                val adapter = bluetoothAdapter()
                    ?: throw IllegalStateException("Bluetooth indisponivel")
                val device: BluetoothDevice = adapter.getRemoteDevice(address)
                adapter.cancelDiscovery()
                val probe = connectAndValidateElm(device)
                if (probe.isBlank()) throw IllegalStateException("ELM327 nao respondeu ATZ")

                runOnUiThread { result.success(device.name ?: address) }
            } catch (error: Throwable) {
                disconnect()
                runOnUiThread {
                    result.error("connect_failed", error.message ?: "Falha ao conectar", null)
                }
            }
        }
    }

    private fun pairDevice(address: String, pin: String?, result: MethodChannel.Result) {
        if (!hasBluetoothPermission()) {
            result.error("permission_denied", "Permissao Bluetooth nao concedida", null)
            return
        }

        thread {
            try {
                val adapter = bluetoothAdapter()
                    ?: throw IllegalStateException("Bluetooth indisponivel")
                if (!adapter.isEnabled) {
                    throw IllegalStateException("Bluetooth desligado")
                }
                adapter.cancelDiscovery()
                val device = adapter.getRemoteDevice(address)
                ensureBonded(device, 60000, pin)
                runOnUiThread { result.success(deviceMap(device, true)) }
            } catch (error: Throwable) {
                runOnUiThread {
                    result.error("pair_failed", error.message ?: "Falha ao parear", null)
                }
            }
        }
    }

    private fun connectAndValidateElm(device: BluetoothDevice): String {
        val errors = mutableListOf<String>()

        tryConnectValidate("SPP direto sem exigir bond", device, errors)?.let {
            return it
        }

        val bondError = try {
            ensureBonded(device, 45000, "1234")
            null
        } catch (error: Throwable) {
            error.message ?: error.javaClass.simpleName
        }
        if (bondError != null) {
            errors.add("bond: $bondError")
        }

        tryConnectValidate("SPP apos tentativa de bond", device, errors)?.let {
            return it
        }

        if (device.bondState == BluetoothDevice.BOND_BONDED) {
            removeBond(device)
            Thread.sleep(700)
            val rebondError = try {
                ensureBonded(device, 45000, "1234")
                null
            } catch (error: Throwable) {
                error.message ?: error.javaClass.simpleName
            }
            if (rebondError != null) {
                errors.add("rebond: $rebondError")
            }
            tryConnectValidate("SPP apos refazer bond", device, errors)?.let {
                return it
            }
        }

        throw IllegalStateException(errors.joinToString(" | "))
    }

    private fun tryConnectValidate(
        label: String,
        device: BluetoothDevice,
        errors: MutableList<String>,
    ): String? {
        disconnect()
        val nextSocket = try {
            connectSocket(device)
        } catch (error: Throwable) {
            errors.add("$label socket: ${error.message ?: error.javaClass.simpleName}")
            return null
        }

        socket = nextSocket
        input = nextSocket.inputStream
        output = nextSocket.outputStream

        return try {
            val probe = sendRawCommand("ATZ", 5000)
            if (probe.isBlank()) {
                errors.add("$label ATZ: sem resposta")
                disconnect()
                null
            } else {
                probe
            }
        } catch (error: Throwable) {
            errors.add("$label ATZ: ${error.message ?: error.javaClass.simpleName}")
            disconnect()
            null
        }
    }

    private fun ensureBonded(device: BluetoothDevice, timeoutMs: Long, pin: String? = null) {
        val receiver = registerPairingReceiver(device, pin)
        when (device.bondState) {
            BluetoothDevice.BOND_BONDED -> {
                unregisterPairingReceiver(receiver)
                return
            }
            BluetoothDevice.BOND_BONDING -> waitForBond(device, timeoutMs)
            BluetoothDevice.BOND_NONE -> {
                if (!device.createBond()) {
                    unregisterPairingReceiver(receiver)
                    throw IllegalStateException("Android recusou iniciar pareamento")
                }
                waitForBond(device, timeoutMs)
            }
        }
        unregisterPairingReceiver(receiver)
        if (device.bondState != BluetoothDevice.BOND_BONDED) {
            throw IllegalStateException("Pareamento nao confirmado. Se aparecer PIN no Android, use 1234 ou 0000; se nao aparecer, tente conectar pelo menu Bluetooth do Android uma vez")
        }
    }

    private fun registerPairingReceiver(target: BluetoothDevice, pin: String?): BroadcastReceiver? {
        unregisterPairingReceiver(pairingReceiver)
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                if (intent.action != BluetoothDevice.ACTION_PAIRING_REQUEST) return
                val device = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    intent.getParcelableExtra(
                        BluetoothDevice.EXTRA_DEVICE,
                        BluetoothDevice::class.java,
                    )
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
                } ?: return
                if (device.address != target.address) return

                val pins = listOfNotNull(pin, "1234", "0000").distinct()
                if (pins.any { trySetPin(device, it) }) {
                    trySetPairingConfirmation(device)
                }
            }
        }
        return try {
            val filter = IntentFilter(BluetoothDevice.ACTION_PAIRING_REQUEST)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                registerReceiver(receiver, filter)
            }
            pairingReceiver = receiver
            receiver
        } catch (_: Throwable) {
            null
        }
    }

    private fun unregisterPairingReceiver(receiver: BroadcastReceiver?) {
        if (receiver == null) return
        try {
            unregisterReceiver(receiver)
        } catch (_: Throwable) {
        }
        if (pairingReceiver == receiver) pairingReceiver = null
    }

    private fun trySetPin(device: BluetoothDevice, pin: String): Boolean {
        return try {
            val method = device.javaClass.getMethod("setPin", ByteArray::class.java)
            method.invoke(device, pin.toByteArray(Charsets.UTF_8))
            true
        } catch (_: Throwable) {
            false
        }
    }

    private fun trySetPairingConfirmation(device: BluetoothDevice) {
        try {
            val method = device.javaClass.getMethod(
                "setPairingConfirmation",
                Boolean::class.javaPrimitiveType,
            )
            method.invoke(device, true)
        } catch (_: Throwable) {
        }
    }

    private fun waitForBond(device: BluetoothDevice, timeoutMs: Long) {
        val deadline = System.currentTimeMillis() + timeoutMs
        while (device.bondState == BluetoothDevice.BOND_BONDING &&
            System.currentTimeMillis() < deadline
        ) {
            Thread.sleep(250)
        }
    }

    private fun connectObdDevice(device: BluetoothDevice): BluetoothSocket {
        return try {
            connectSocket(device)
        } catch (pairedError: Throwable) {
            throw IllegalStateException(
                "Pareado, mas falhou ao abrir SPP: ${pairedError.message ?: pairedError.javaClass.simpleName}",
            )
        }
    }

    private fun connectSocket(device: BluetoothDevice): BluetoothSocket {
        val errors = mutableListOf<String>()

        trySocket("secure UUID", errors) {
            device.createRfcommSocketToServiceRecord(sppUuid)
        }?.let { return it }

        trySocket("insecure UUID", errors) {
            device.createInsecureRfcommSocketToServiceRecord(sppUuid)
        }?.let { return it }

        trySocket("secure channel 1", errors) {
            val method = device.javaClass.getMethod(
                "createRfcommSocket",
                Int::class.javaPrimitiveType,
            )
            method.invoke(device, 1) as BluetoothSocket
        }?.let { return it }

        trySocket("insecure channel 1", errors) {
            val method = device.javaClass.getMethod(
                "createInsecureRfcommSocket",
                Int::class.javaPrimitiveType,
            )
            method.invoke(device, 1) as BluetoothSocket
        }?.let { return it }

        throw IllegalStateException(errors.joinToString(" | "))
    }

    private fun trySocket(
        label: String,
        errors: MutableList<String>,
        factory: () -> BluetoothSocket,
    ): BluetoothSocket? {
        val nextSocket = try {
            factory()
        } catch (error: Throwable) {
            errors.add("$label: ${error.message ?: error.javaClass.simpleName}")
            return null
        }
        return try {
            nextSocket.connect()
            nextSocket
        } catch (error: Throwable) {
            try {
                nextSocket.close()
            } catch (_: Throwable) {
            }
            errors.add("$label: ${error.message ?: error.javaClass.simpleName}")
            null
        }
    }

    private fun forgetDevice(address: String, result: MethodChannel.Result) {
        if (!hasBluetoothPermission()) {
            result.error("permission_denied", "Permissao Bluetooth nao concedida", null)
            return
        }

        thread {
            try {
                disconnect()
                val adapter = bluetoothAdapter()
                    ?: throw IllegalStateException("Bluetooth indisponivel")
                val device = adapter.getRemoteDevice(address)
                removeBond(device)
                runOnUiThread { result.success(true) }
            } catch (error: Throwable) {
                runOnUiThread {
                    result.error("forget_failed", error.message ?: "Falha ao esquecer", null)
                }
            }
        }
    }

    private fun removeBond(device: BluetoothDevice) {
        if (device.bondState != BluetoothDevice.BOND_BONDED) return
        try {
            val method = device.javaClass.getMethod("removeBond")
            method.invoke(device)
        } catch (_: Throwable) {
        }
    }

    private fun sendCommand(command: String, timeoutMs: Int, result: MethodChannel.Result) {
        if (output == null || input == null) {
            result.error("not_connected", "ELM327 nao conectado", null)
            return
        }

        thread {
            try {
                val raw = sendRawCommand(command, timeoutMs)
                if (raw.isBlank()) {
                    runOnUiThread {
                        result.error("timeout", "Timeout aguardando resposta", null)
                    }
                } else {
                    runOnUiThread { result.success(raw) }
                }
            } catch (error: Throwable) {
                runOnUiThread {
                    result.error("command_failed", error.message ?: "Falha ao enviar comando", null)
                }
            }
        }
    }

    private fun sendRawCommand(command: String, timeoutMs: Int): String {
        val out = output ?: return ""
        val inp = input ?: return ""

        while (inp.available() > 0) {
            inp.read()
        }

        out.write((command.trim() + "\r").toByteArray(Charsets.US_ASCII))
        out.flush()

        val deadline = System.currentTimeMillis() + timeoutMs
        val buffer = ByteArray(256)
        val response = StringBuilder()
        while (System.currentTimeMillis() < deadline) {
            val available = inp.available()
            if (available > 0) {
                val read = inp.read(buffer, 0, minOf(buffer.size, available))
                if (read > 0) {
                    response.append(String(buffer, 0, read, Charsets.US_ASCII))
                    if (response.contains(">")) break
                }
            } else {
                Thread.sleep(20)
            }
        }

        return response.toString().replace(">", "").trim()
    }

    private fun disconnect() {
        try {
            input?.close()
        } catch (_: Throwable) {
        }
        try {
            output?.close()
        } catch (_: Throwable) {
        }
        try {
            socket?.close()
        } catch (_: Throwable) {
        }
        input = null
        output = null
        socket = null
    }

    private fun finishScan() {
        val adapter = bluetoothAdapter()
        try {
            if (adapter?.isDiscovering == true) adapter.cancelDiscovery()
        } catch (_: Throwable) {
        }
        stopBleScan(adapter)
        try {
            scanReceiver?.let { unregisterReceiver(it) }
        } catch (_: Throwable) {
        }
        scanReceiver = null

        val result = scanResult ?: return
        scanResult = null
        val devices = scanDevices.values.sortedWith(compareByDescending<Map<String, Any?>> {
            it["elmCandidate"] == true
        }.thenByDescending {
            it["paired"] == true
        }.thenBy {
            (it["name"] as? String)?.lowercase(Locale.US) ?: ""
        })
        runOnUiThread { result.success(devices) }
    }

    private fun finishScanWithError(code: String, message: String) {
        stopBleScan(bluetoothAdapter())
        try {
            scanReceiver?.let { unregisterReceiver(it) }
        } catch (_: Throwable) {
        }
        scanReceiver = null
        val result = scanResult ?: return
        scanResult = null
        runOnUiThread { result.error(code, message, null) }
    }

    private fun stopBleScan(adapter: BluetoothAdapter?) {
        val callback = bleScanCallback ?: return
        try {
            adapter?.bluetoothLeScanner?.stopScan(callback)
        } catch (_: Throwable) {
        }
        bleScanCallback = null
    }

    private fun deviceMap(
        device: BluetoothDevice,
        paired: Boolean,
        transport: String = "CLASSIC",
        rssi: Int? = null,
    ): Map<String, Any?> {
        val rawName = try {
            device.name
        } catch (_: Throwable) {
            null
        }
        val name = rawName?.trim()?.takeIf { it.isNotEmpty() } ?: "Dispositivo sem nome"
        val upperName = name.uppercase(Locale.US)
        val elmCandidate = upperName.contains("ELM") ||
            upperName.contains("OBD") ||
            upperName.contains("V-LINK") ||
            upperName.contains("VEEPEAK") ||
            upperName.contains("CARISTA")
        return mapOf(
            "name" to name,
            "address" to device.address,
            "paired" to paired,
            "bondState" to device.bondState,
            "type" to device.type,
            "transport" to transport,
            "rssi" to rssi,
            "elmCandidate" to elmCandidate,
        )
    }

    private fun bluetoothAdapter(): BluetoothAdapter? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val manager = getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
            manager.adapter
        } else {
            @Suppress("DEPRECATION")
            BluetoothAdapter.getDefaultAdapter()
        }
    }

    private fun hasBluetoothPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true
        return checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) ==
            PackageManager.PERMISSION_GRANTED
    }

    private fun hasScanPermission(): Boolean {
        val hasLocation =
            checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return hasLocation
        return hasLocation &&
            checkSelfPermission(Manifest.permission.BLUETOOTH_SCAN) == PackageManager.PERMISSION_GRANTED
    }

    private fun isLocationEnabledForScan(): Boolean {
        val manager = getSystemService(Context.LOCATION_SERVICE) as? LocationManager
            ?: return true
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            manager.isLocationEnabled
        } else {
            @Suppress("DEPRECATION")
            manager.isProviderEnabled(LocationManager.GPS_PROVIDER) ||
                manager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)
        }
    }
}
