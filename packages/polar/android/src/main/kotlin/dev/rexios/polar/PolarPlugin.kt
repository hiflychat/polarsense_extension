package dev.rexios.polar

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.lifecycle.Lifecycle.Event
import androidx.lifecycle.LifecycleEventObserver
import com.google.gson.GsonBuilder
import com.google.gson.JsonDeserializationContext
import com.google.gson.JsonDeserializer
import com.google.gson.JsonElement
import com.google.gson.JsonPrimitive
import com.google.gson.JsonSerializationContext
import com.google.gson.JsonSerializer
import com.polar.androidcommunications.api.ble.model.DisInfo
import com.polar.androidcommunications.api.ble.model.gatt.client.ChargeState
import com.polar.androidcommunications.api.ble.model.gatt.client.PowerSourcesState
import com.polar.androidcommunications.api.ble.model.gatt.client.psftp.BlePsFtpUtils
import com.polar.sdk.api.PolarBleApi
import com.polar.sdk.api.PolarBleApi.PolarBleSdkFeature
import com.polar.sdk.api.PolarBleApi.PolarDeviceDataType
import com.polar.sdk.api.PolarBleApiCallbackProvider
import com.polar.sdk.api.PolarBleApiDefaultImpl
import com.polar.sdk.api.PolarH10OfflineExerciseApi.RecordingInterval
import com.polar.sdk.api.PolarH10OfflineExerciseApi.SampleType
import com.polar.sdk.api.errors.PolarOperationNotSupported
import com.polar.sdk.api.model.LedConfig
import com.polar.sdk.api.model.PolarDeviceInfo
import com.polar.sdk.api.model.PolarExerciseData
import com.polar.sdk.api.model.PolarExerciseEntry
import com.polar.sdk.api.model.PolarFirstTimeUseConfig
import com.polar.sdk.api.model.PolarHealthThermometerData
import com.polar.sdk.api.model.PolarHrData
import com.polar.sdk.api.model.PolarOfflineRecordingData
import com.polar.sdk.api.model.PolarOfflineRecordingEntry
import com.polar.sdk.api.model.PolarSensorSetting
import com.polar.sdk.api.model.trainingsession.PolarTrainingSessionReference
import fi.polar.remote.representation.protobuf.ExerciseSamples.PbExerciseSamples
import fi.polar.remote.representation.protobuf.ExerciseSamples2.PbExerciseSamples2
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.embedding.engine.plugins.lifecycle.FlutterLifecycleAdapter
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.EventChannel.EventSink
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.reactivex.rxjava3.core.Completable
import io.reactivex.rxjava3.core.Single
import io.reactivex.rxjava3.disposables.Disposable
import io.reactivex.rxjava3.schedulers.Schedulers
import protocol.PftpResponse.PbPFtpDirectory
import java.io.ByteArrayInputStream
import java.lang.reflect.Type
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import java.util.UUID
import java.util.zip.GZIPInputStream

fun Any?.discard() = Unit

object LocalDateTimeSerializer : JsonDeserializer<LocalDateTime>, JsonSerializer<LocalDateTime> {
    override fun deserialize(
        json: JsonElement?,
        typeOfT: Type?,
        context: JsonDeserializationContext?,
    ): LocalDateTime =
        Instant
            .ofEpochMilli(json?.asJsonPrimitive?.asLong ?: 0)
            .atZone(ZoneId.systemDefault())
            .toLocalDateTime()

    override fun serialize(
        src: LocalDateTime?,
        typeOfSrc: Type?,
        context: JsonSerializationContext?,
    ): JsonElement =
        JsonPrimitive(
            src?.atZone(ZoneId.systemDefault())?.toInstant()?.toEpochMilli() ?: 0,
        )
}

private fun runOnUiThread(runnable: () -> Unit) {
    Handler(Looper.getMainLooper()).post { runnable() }
}

private val gson =
    GsonBuilder()
        .registerTypeAdapter(LocalDateTime::class.java, LocalDateTimeSerializer)
        .create()

private var wrapperInternal: PolarWrapper? = null
private val wrapper: PolarWrapper
    get() = wrapperInternal!!

/** PolarPlugin */
class PolarPlugin :
    FlutterPlugin,
    MethodCallHandler,
    EventChannel.StreamHandler,
    ActivityAware {
    // Binary messenger for dynamic EventChannel registration
    private lateinit var messenger: BinaryMessenger

    // Method channel
    private lateinit var methodChannel: MethodChannel

    // Event channel
    private lateinit var eventChannel: EventChannel

    // Search channel
    private lateinit var searchChannel: EventChannel

    // Context
    private lateinit var context: Context

    // Streaming channels
    private val streamingChannels = mutableMapOf<String, StreamingChannel>()

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        messenger = flutterPluginBinding.binaryMessenger

        methodChannel = MethodChannel(flutterPluginBinding.binaryMessenger, "polar/methods")
        methodChannel.setMethodCallHandler(this)

        eventChannel = EventChannel(flutterPluginBinding.binaryMessenger, "polar/events")
        eventChannel.setStreamHandler(this)

        searchChannel = EventChannel(flutterPluginBinding.binaryMessenger, "polar/search")
        searchChannel.setStreamHandler(searchHandler)

        context = flutterPluginBinding.applicationContext
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        searchChannel.setStreamHandler(null)
        streamingChannels.values.forEach { it.dispose() }
        shutDown()
    }

    private fun initApi() {
        if (wrapperInternal == null) {
            wrapperInternal = PolarWrapper(context)
        }
    }

    override fun onMethodCall(
        call: MethodCall,
        result: Result,
    ) {
        initApi()

        when (call.method) {
            "shutDown" -> {
                shutDown()
                result.success(null)
            }

            "connectToDevice" -> {
                wrapper.api.connectToDevice(call.arguments as String)
                result.success(null)
            }

            "disconnectFromDevice" -> {
                wrapper.api.disconnectFromDevice(call.arguments as String)
                result.success(null)
            }

            "getAvailableOnlineStreamDataTypes" -> {
                getAvailableOnlineStreamDataTypes(call, result)
            }

            "getAvailableHrServiceDataTypes" -> {
                getAvailableHrServiceDataTypes(call, result)
            }

            "requestStreamSettings" -> {
                requestStreamSettings(call, result)
            }

            "createStreamingChannel" -> {
                createStreamingChannel(call, result)
            }

            "startRecording" -> {
                startRecording(call, result)
            }

            "stopRecording" -> {
                stopRecording(call, result)
            }

            "requestRecordingStatus" -> {
                requestRecordingStatus(call, result)
            }

            "listExercises" -> {
                listExercises(call, result)
            }

            "fetchExercise" -> {
                fetchExercise(call, result)
            }

            "removeExercise" -> {
                removeExercise(call, result)
            }

            "inspectDeviceStorage" -> {
                inspectDeviceStorage(call, result)
            }

            "setLedConfig" -> {
                setLedConfig(call, result)
            }

            "doFactoryReset" -> {
                doFactoryReset(call, result)
            }

            "enableSdkMode" -> {
                enableSdkMode(call, result)
            }

            "disableSdkMode" -> {
                disableSdkMode(call, result)
            }

            "isSdkModeEnabled" -> {
                isSdkModeEnabled(call, result)
            }

            "doFirstTimeUse" -> {
                doFirstTimeUse(call, result)
            }

            "isFtuDone" -> {
                isFtuDone(call, result)
            }

            else -> {
                result.notImplemented()
            }
        }
    }

    override fun onListen(
        arguments: Any?,
        events: EventSink,
    ) {
        initApi()
        wrapper.addSink(arguments as Int, events)
    }

    override fun onCancel(arguments: Any?) {
        val id = arguments as? Int ?: return
        wrapper.removeSink(id)
    }

    private val searchHandler =
        object : EventChannel.StreamHandler {
            private var searchSubscription: Disposable? = null

            override fun onListen(
                arguments: Any?,
                events: EventSink,
            ) {
                initApi()

                searchSubscription =
                    wrapper.api.searchForDevice().subscribe({
                        runOnUiThread { events.success(gson.toJson(it)) }
                    }, {
                        runOnUiThread {
                            events.error(it.toString(), it.message, null)
                        }
                    }, {
                        runOnUiThread { events.endOfStream() }
                    })
            }

            override fun onCancel(arguments: Any?) {
                dispose()
            }

            fun dispose() {
                searchSubscription?.dispose()
                searchSubscription = null
            }
        }

    private fun createStreamingChannel(
        call: MethodCall,
        result: Result,
    ) {
        val arguments = call.arguments as List<*>
        val name = arguments[0] as String
        val identifier = arguments[1] as String
        val feature = gson.fromJson(arguments[2] as String, PolarDeviceDataType::class.java)

        if (streamingChannels[name] == null) {
            streamingChannels[name] =
                StreamingChannel(messenger, name, wrapper.api, identifier, feature)
        }

        result.success(null)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        val lifecycle = FlutterLifecycleAdapter.getActivityLifecycle(binding)
        lifecycle.addObserver(
            LifecycleEventObserver { _, event ->
                when (event) {
                    Event.ON_RESUME -> {
                        wrapperInternal?.api?.foregroundEntered()
                    }

                    Event.ON_DESTROY -> {
                        shutDown()
                    }

                    else -> {}
                }
            },
        )
    }

    override fun onDetachedFromActivityForConfigChanges() {}

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {}

    override fun onDetachedFromActivity() {}

    private fun shutDown() {
        streamingChannels.values.forEach { it.dispose() }
        streamingChannels.clear()
        searchHandler.dispose()
        if (wrapperInternal != null) {
            try {
                wrapper.api.shutDown()
            } catch (_: Exception) {
            }
            wrapperInternal = null
        }
    }

    private fun getAvailableOnlineStreamDataTypes(
        call: MethodCall,
        result: Result,
    ) {
        val identifier = call.arguments as String

        wrapper.api
            .getAvailableOnlineStreamDataTypes(identifier)
            .subscribe({
                runOnUiThread { result.success(gson.toJson(it)) }
            }, {
                runOnUiThread {
                    result.error(it.toString(), it.message, null)
                }
            })
            .discard()
    }

    private fun getAvailableHrServiceDataTypes(
        call: MethodCall,
        result: Result,
    ) {
        val identifier = call.arguments as String

        wrapper.api
            .getAvailableHRServiceDataTypes(identifier)
            .subscribe({
                runOnUiThread { result.success(gson.toJson(it)) }
            }, {
                runOnUiThread {
                    result.error(it.toString(), it.message, null)
                }
            })
            .discard()
    }

    private fun requestStreamSettings(
        call: MethodCall,
        result: Result,
    ) {
        val arguments = call.arguments as List<*>
        val identifier = arguments[0] as String
        val feature = gson.fromJson(arguments[1] as String, PolarDeviceDataType::class.java)

        wrapper.api
            .requestStreamSettings(identifier, feature)
            .subscribe({
                runOnUiThread { result.success(gson.toJson(it)) }
            }, {
                runOnUiThread {
                    result.error(it.toString(), it.message, null)
                }
            })
            .discard()
    }

    private fun hasCause(
        t: Throwable?,
        target: Class<out Throwable>,
    ): Boolean {
        var cur = t
        var depth = 0
        while (cur != null && depth < 12) {
            if (target.isInstance(cur)) return true
            cur = cur.cause
            depth++
        }
        return false
    }

    private fun isNoSuchFileOrDirectory(t: Throwable?): Boolean {
        var cur = t
        var depth = 0
        while (cur != null && depth < 12) {
            if (cur is BlePsFtpUtils.PftpResponseError && cur.error == 103) return true
            val msg = cur.message ?: ""
            if (msg.contains("NO_SUCH_FILE_OR_DIRECTORY", ignoreCase = true)) return true
            cur = cur.cause
            depth++
        }
        return false
    }

    private fun gunzipIfNeeded(
        rawBytes: ByteArray,
        path: String,
    ): ByteArray {
        if (!path.endsWith(".GZB", ignoreCase = true)) return rawBytes
        return GZIPInputStream(ByteArrayInputStream(rawBytes)).use { it.readBytes() }
    }

    private fun parsePbExerciseSamples(bytes: ByteArray): PolarExerciseData {
        val samples = PbExerciseSamples.parseFrom(bytes)
        val defaultInterval =
            if (samples.hasRecordingInterval() && samples.recordingInterval.seconds > 0) {
                samples.recordingInterval.seconds
            } else {
                1
            }

        if (samples.hasRrSamples() && samples.rrSamples.rrIntervalsList.isNotEmpty()) {
            return PolarExerciseData(defaultInterval, samples.rrSamples.rrIntervalsList)
        }
        if (samples.heartRateSamplesList.isNotEmpty()) {
            return PolarExerciseData(defaultInterval, samples.heartRateSamplesList)
        }
        for (intervalList in samples.exerciseIntervalledSampleListList) {
            val listInterval =
                if (intervalList.hasRecordingIntervalMs() && intervalList.recordingIntervalMs > 0) {
                    kotlin.math.max(1, intervalList.recordingIntervalMs / 1000)
                } else {
                    defaultInterval
                }
            if (intervalList.hasRrSamples() && intervalList.rrSamples.rrIntervalsList.isNotEmpty()) {
                return PolarExerciseData(listInterval, intervalList.rrSamples.rrIntervalsList)
            }
            if (intervalList.heartRateSamplesList.isNotEmpty()) {
                return PolarExerciseData(listInterval, intervalList.heartRateSamplesList)
            }
        }
        return PolarExerciseData(defaultInterval, emptyList())
    }

    private fun parsePbExerciseSamples2(bytes: ByteArray): PolarExerciseData {
        val samples2 = PbExerciseSamples2.parseFrom(bytes)
        for (listItem in samples2.exerciseIntervalledSample2ListList) {
            if (listItem.heartRateSamplesCount > 0 || listItem.syncPointList.any { it.hasHeartRateSample() }) {
                val intervalSec = kotlin.math.max(1, listItem.recordingIntervalMs / 1000)
                val syncPoints = listItem.syncPointList.associateBy { it.index }
                val hrOut = mutableListOf<Int>()
                var currentHr = 0
                for (i in 0 until listItem.heartRateSamplesCount) {
                    val sp = syncPoints[i]
                    if (sp != null && sp.hasHeartRateSample()) {
                        currentHr = sp.heartRateSample
                    }
                    currentHr += listItem.getHeartRateSamples(i)
                    hrOut.add(currentHr.coerceIn(0, 255))
                }
                if (hrOut.isNotEmpty()) {
                    return PolarExerciseData(intervalSec, hrOut)
                }
            }
        }
        return PolarExerciseData(1, emptyList())
    }

    private fun convertPpiOfflineToExerciseData(data: PolarOfflineRecordingData.PpiOfflineRecording): PolarExerciseData {
        val ppiOut = mutableListOf<Int>()
        var accMs = 0L
        var nextSecMs = 1000L
        var lastValidPpi = 800
        for (sample in data.data.samples) {
            val stepMs =
                when {
                    sample.ppi in 250..2500 -> sample.ppi.toLong()
                    sample.hr in 30..220 -> 60000L / sample.hr
                    else -> 800L
                }
            val valueMs =
                when {
                    !sample.blockerBit && sample.ppi in 300..2000 -> sample.ppi
                    sample.hr in 30..220 -> 60000 / sample.hr
                    else -> lastValidPpi
                }
            lastValidPpi = valueMs
            accMs += stepMs
            while (accMs >= nextSecMs) {
                ppiOut.add(valueMs)
                nextSecMs += 1000L
            }
        }
        return PolarExerciseData(1, ppiOut)
    }

    private fun pickBestSamplePath(
        basePath: String,
        dir: PbPFtpDirectory,
    ): String? {
        val priorities = listOf("SAMPLES.BPB", "SAMPLES.GZB", "SAMPLES2.GZB")
        for (candidate in priorities) {
            val match = dir.entriesList.firstOrNull { it.name.equals(candidate, ignoreCase = true) && it.size > 0 }
            if (match != null) {
                return basePath + match.name
            }
        }
        return null
    }

    private fun scanV2ExercisesAndOfflineBlocking(identifier: String): List<PolarExerciseEntry> {
        val results = mutableListOf<PolarExerciseEntry>()
        val formatter = DateTimeFormatter.ofPattern("yyyyMMddHHmmss", Locale.US)
        var u0Error: Throwable? = null

        try {
            val u0Bytes = wrapper.api.getFile(identifier, "/U/0/").blockingGet()
            val u0Dir = PbPFtpDirectory.parseFrom(u0Bytes)
            val dateDirs =
                u0Dir.entriesList
                    .map { it.name }
                    .filter { it.matches(Regex("^\\d{8}/$")) }
                    .sortedDescending()
                    .take(45)

            for (dateDir in dateDirs) {
                val dateBytes = wrapper.api.getFile(identifier, "/U/0/$dateDir").blockingGet()
                val dateListing = PbPFtpDirectory.parseFrom(dateBytes)
                if (dateListing.entriesList.none { it.name == "E/" }) continue

                val eBytes = wrapper.api.getFile(identifier, "/U/0/${dateDir}E/").blockingGet()
                val eListing = PbPFtpDirectory.parseFrom(eBytes)
                val timeDirs =
                    eListing.entriesList
                        .map { it.name }
                        .filter { it.matches(Regex("^\\d{6}/$")) }
                        .sortedDescending()

                val datePart = dateDir.dropLast(1)
                for (timeDir in timeDirs) {
                    val timePart = timeDir.dropLast(1)
                    val sessionPath = "/U/0/${dateDir}E/${timeDir}"
                    val sessionBytes = wrapper.api.getFile(identifier, sessionPath).blockingGet()
                    val sessionListing = PbPFtpDirectory.parseFrom(sessionBytes)

                    val parsedDate =
                        try {
                            LocalDateTime.parse("$datePart$timePart", formatter)
                        } catch (e: Exception) {
                            Log.w("PolarPlugin", "Date parse skipped for $datePart$timePart: ${e.message}")
                            continue
                        }

                    val directSample = pickBestSamplePath(sessionPath, sessionListing)
                    if (directSample != null) {
                        results.add(PolarExerciseEntry(directSample, parsedDate, "$datePart$timePart"))
                    }

                    val subDirs =
                        sessionListing.entriesList
                            .map { it.name }
                            .filter { it.matches(Regex("^\\d+/$")) }
                            .sorted()
                    for (subDir in subDirs) {
                        val subPath = "$sessionPath$subDir"
                        val subBytes = wrapper.api.getFile(identifier, subPath).blockingGet()
                        val subListing = PbPFtpDirectory.parseFrom(subBytes)
                        val subSample = pickBestSamplePath(subPath, subListing)
                        if (subSample != null) {
                            val subSuffix = if (subDir == "00/") "" else "_${subDir.dropLast(1)}"
                            results.add(PolarExerciseEntry(subSample, parsedDate, "$datePart$timePart$subSuffix"))
                        }
                    }
                }
            }
        } catch (e: Throwable) {
            if (hasCause(e, PolarOperationNotSupported::class.java)) {
                // H10 or legacy file system: use SDK native listExercises
                return wrapper.api.listExercises(identifier).toList().blockingGet()
            } else if (!isNoSuchFileOrDirectory(e)) {
                Log.w("PolarPlugin", "Scanning /U/0/ failed: ${e.message}")
                u0Error = e
            }
        }

        // Also scan SDK Offline Recording API entries (/U/0/YYYYMMDD/R/HHMMSS/*.REC)
        var offlineSuccess = false
        try {
            val offlineList = wrapper.api.listOfflineRecordings(identifier).toList().blockingGet()
            offlineSuccess = true
            val validEntries =
                offlineList.filter {
                    it.size > 0 &&
                        (it.type == PolarDeviceDataType.PPI || it.type == PolarDeviceDataType.HR)
                }
            val bySessionPrefix = validEntries.groupBy { it.path.substringBeforeLast("/") }
            for ((_, group) in bySessionPrefix) {
                val chosen =
                    group.firstOrNull { it.type == PolarDeviceDataType.PPI }
                        ?: group.firstOrNull { it.type == PolarDeviceDataType.HR }
                        ?: continue
                val idStr = "rec_${chosen.date.format(formatter)}_${chosen.type.name}"
                results.add(
                    PolarExerciseEntry(
                        "OFFLINE_REC::${chosen.type.name}::${chosen.path}",
                        chosen.date,
                        idStr,
                    ),
                )
            }
        } catch (e: Throwable) {
            if (!hasCause(e, PolarOperationNotSupported::class.java) && !isNoSuchFileOrDirectory(e)) {
                Log.w("PolarPlugin", "listOfflineRecordings warning: ${e.message}")
            }
        }

        if (u0Error != null && results.isEmpty() && !offlineSuccess) {
            throw u0Error
        }

        return results.sortedByDescending { it.date }
    }

    private fun startRecording(
        call: MethodCall,
        result: Result,
    ) {
        val arguments = call.arguments as List<*>
        val identifier = arguments[0] as String
        val exerciseId = arguments[1] as String
        val interval = gson.fromJson(arguments[2] as String, RecordingInterval::class.java)
        val sampleType = gson.fromJson(arguments[3] as String, SampleType::class.java)

        wrapper.api
            .startRecording(identifier, exerciseId, interval, sampleType)
            .onErrorResumeNext { err ->
                if (hasCause(err, PolarOperationNotSupported::class.java)) {
                    val dataType =
                        if (sampleType == SampleType.RR) {
                            PolarDeviceDataType.PPI
                        } else {
                            PolarDeviceDataType.HR
                        }
                    wrapper.api.startOfflineRecording(identifier, dataType)
                } else {
                    Completable.error(err)
                }
            }
            .subscribe({
                runOnUiThread { result.success(null) }
            }, {
                runOnUiThread {
                    result.error(it.toString(), it.message, null)
                }
            })
            .discard()
    }

    private fun stopRecording(
        call: MethodCall,
        result: Result,
    ) {
        val identifier = call.arguments as String

        wrapper.api
            .stopRecording(identifier)
            .onErrorResumeNext { err ->
                if (hasCause(err, PolarOperationNotSupported::class.java)) {
                    wrapper.api
                        .getOfflineRecordingStatus(identifier)
                        .flatMapCompletable { activeTypes ->
                            if (activeTypes.isEmpty()) {
                                Completable.complete()
                            } else {
                                Completable.concat(
                                    activeTypes.map { dataType ->
                                        wrapper.api.stopOfflineRecording(identifier, dataType)
                                    },
                                )
                            }
                        }
                } else {
                    Completable.error(err)
                }
            }
            .subscribe({
                runOnUiThread { result.success(null) }
            }, {
                runOnUiThread {
                    result.error(it.toString(), it.message, null)
                }
            })
            .discard()
    }

    private fun requestRecordingStatus(
        call: MethodCall,
        result: Result,
    ) {
        val identifier = call.arguments as String

        wrapper.api
            .requestRecordingStatus(identifier)
            .map { Pair(it.first, it.second) }
            .onErrorResumeNext { err ->
                if (hasCause(err, PolarOperationNotSupported::class.java)) {
                    wrapper.api.getOfflineRecordingStatus(identifier).map { activeTypes ->
                        Pair(
                            activeTypes.isNotEmpty(),
                            activeTypes.joinToString(",") { it.name },
                        )
                    }
                } else {
                    Single.error(err)
                }
            }
            .subscribe({
                runOnUiThread { result.success(listOf(it.first, it.second)) }
            }, {
                runOnUiThread {
                    result.error(it.toString(), it.message, null)
                }
            })
            .discard()
    }

    private fun listExercises(
        call: MethodCall,
        result: Result,
    ) {
        val identifier = call.arguments as String

        Single
            .fromCallable {
                scanV2ExercisesAndOfflineBlocking(identifier).map { gson.toJson(it) }
            }.subscribeOn(Schedulers.io())
            .subscribe({ exercisesJson ->
                runOnUiThread {
                    result.success(exercisesJson)
                }
            }, { err ->
                runOnUiThread {
                    result.error(err.toString(), err.message, null)
                }
            })
            .discard()
    }

    private fun fetchExercise(
        call: MethodCall,
        result: Result,
    ) {
        val arguments = call.arguments as List<*>
        val identifier = arguments[0] as String
        val entry = gson.fromJson(arguments[1] as String, PolarExerciseEntry::class.java)

        Single
            .fromCallable {
                when {
                    entry.path.startsWith("OFFLINE_REC::") -> {
                        val parts = entry.path.split("::", limit = 3)
                        val type = PolarDeviceDataType.valueOf(parts[1])
                        val realPath = parts[2]
                        val allOffline = wrapper.api.listOfflineRecordings(identifier).toList().blockingGet()
                        val matchedEntry =
                            allOffline.firstOrNull { it.path == realPath }
                                ?: PolarOfflineRecordingEntry(realPath, 0L, entry.date, type)
                        val data = wrapper.api.getOfflineRecord(identifier, matchedEntry).blockingGet()
                        when (data) {
                            is PolarOfflineRecordingData.HrOfflineRecording -> {
                                PolarExerciseData(1, data.data.samples.map { it.hr })
                            }
                            is PolarOfflineRecordingData.PpiOfflineRecording -> {
                                convertPpiOfflineToExerciseData(data)
                            }
                            else -> PolarExerciseData(1, emptyList())
                        }
                    }

                    entry.path.startsWith("/U/0/") -> {
                        val rawBytes = wrapper.api.getFile(identifier, entry.path).blockingGet()
                        val bytes = gunzipIfNeeded(rawBytes, entry.path)
                        if (entry.path.contains("SAMPLES2", ignoreCase = true)) {
                            parsePbExerciseSamples2(bytes)
                        } else {
                            parsePbExerciseSamples(bytes)
                        }
                    }

                    else -> {
                        wrapper.api.fetchExercise(identifier, entry).blockingGet()
                    }
                }
            }.subscribeOn(Schedulers.io())
            .subscribe({ exerciseData ->
                runOnUiThread {
                    result.success(gson.toJson(exerciseData))
                }
            }, { err ->
                runOnUiThread {
                    result.error(err.toString(), err.message, null)
                }
            })
            .discard()
    }

    private fun removeExercise(
        call: MethodCall,
        result: Result,
    ) {
        val arguments = call.arguments as List<*>
        val identifier = arguments[0] as String
        val entry = gson.fromJson(arguments[1] as String, PolarExerciseEntry::class.java)

        Completable
            .fromAction {
                when {
                    entry.path.startsWith("OFFLINE_REC::") -> {
                        val parts = entry.path.split("::", limit = 3)
                        val type = PolarDeviceDataType.valueOf(parts[1])
                        val realPath = parts[2]
                        val allOffline = wrapper.api.listOfflineRecordings(identifier).toList().blockingGet()
                        val matchedEntry =
                            allOffline.firstOrNull { it.path == realPath }
                                ?: PolarOfflineRecordingEntry(realPath, 0L, entry.date, type)
                        wrapper.api.removeOfflineRecord(identifier, matchedEntry).blockingAwait()
                    }

                    entry.path.startsWith("/U/0/") -> {
                        val ref =
                            PolarTrainingSessionReference(
                                date = entry.date.toLocalDate(),
                                path = entry.path,
                                trainingDataTypes = emptyList(),
                                exercises = emptyList(),
                                fileSize = 0L,
                            )
                        wrapper.api.deleteTrainingSession(identifier, ref).blockingAwait()
                    }

                    else -> {
                        wrapper.api.removeExercise(identifier, entry).blockingAwait()
                    }
                }
            }.subscribeOn(Schedulers.io())
            .subscribe({
                runOnUiThread { result.success(null) }
            }, { err ->
                runOnUiThread {
                    result.error(err.toString(), err.message, null)
                }
            })
            .discard()
    }

    private fun inspectDeviceStorage(
        call: MethodCall,
        result: Result,
    ) {
        val identifier = call.arguments as String

        Single
            .fromCallable {
                val diag = mutableMapOf<String, Any?>()
                val errors = mutableListOf<String>()

                diag["fileTransferReady"] =
                    wrapper.api.isFeatureReady(identifier, PolarBleSdkFeature.FEATURE_POLAR_FILE_TRANSFER)
                diag["offlineRecordingReady"] =
                    wrapper.api.isFeatureReady(identifier, PolarBleSdkFeature.FEATURE_POLAR_OFFLINE_RECORDING)
                diag["h10ExerciseReady"] =
                    wrapper.api.isFeatureReady(identifier, PolarBleSdkFeature.FEATURE_POLAR_H10_EXERCISE_RECORDING)

                try {
                    val space = wrapper.api.getDiskSpace(identifier).blockingGet()
                    diag["diskFreeBytes"] = space.freeSpace
                    diag["diskTotalBytes"] = space.totalSpace
                } catch (e: Throwable) {
                    errors.add("getDiskSpace: ${e.message}")
                }

                val u0Paths = mutableListOf<String>()
                fun listRecursiveDiag(
                    path: String,
                    depth: Int,
                ) {
                    if (depth > 4 || u0Paths.size >= 80) return
                    val bytes = wrapper.api.getFile(identifier, path).blockingGet()
                    val dir = PbPFtpDirectory.parseFrom(bytes)
                    for (item in dir.entriesList) {
                        val full = "$path${item.name}"
                        u0Paths.add("$full (${item.size}B)")
                        if (item.name.endsWith("/") && depth < 4 && u0Paths.size < 80) {
                            listRecursiveDiag(full, depth + 1)
                        }
                    }
                }

                try {
                    listRecursiveDiag("/U/0/", 0)
                } catch (e: Throwable) {
                    errors.add("/U/0/ scan: ${e.message}")
                }
                diag["u0Paths"] = u0Paths

                val offlineDesc = mutableListOf<String>()
                try {
                    val entries = wrapper.api.listOfflineRecordings(identifier).toList().blockingGet()
                    for (entry in entries) {
                        offlineDesc.add("${entry.type.name}: ${entry.path} (${entry.size}B, ${entry.date})")
                    }
                } catch (e: Throwable) {
                    errors.add("listOfflineRecordings: ${e.message}")
                }
                diag["offlineEntries"] = offlineDesc
                diag["errors"] = errors

                gson.toJson(diag)
            }.subscribeOn(Schedulers.io())
            .subscribe({ jsonStr ->
                runOnUiThread { result.success(jsonStr) }
            }, { err ->
                runOnUiThread { result.error(err.toString(), err.message, null) }
            })
            .discard()
    }

    private fun setLedConfig(
        call: MethodCall,
        result: Result,
    ) {
        val arguments = call.arguments as List<*>
        val identifier = arguments[0] as String
        val config = gson.fromJson(arguments[1] as String, LedConfig::class.java)

        wrapper.api
            .setLedConfig(identifier, config)
            .subscribe({
                runOnUiThread { result.success(null) }
            }, {
                runOnUiThread {
                    result.error(it.toString(), it.message, null)
                }
            })
            .discard()
    }

    private fun doFactoryReset(
        call: MethodCall,
        result: Result,
    ) {
        val arguments = call.arguments as List<*>
        val identifier = arguments[0] as String
        val preservePairingInformation = arguments[1] as Boolean

        wrapper.api
            .doFactoryReset(identifier, preservePairingInformation)
            .subscribe({
                runOnUiThread { result.success(null) }
            }, {
                runOnUiThread {
                    result.error(it.toString(), it.message, null)
                }
            })
            .discard()
    }

    private fun enableSdkMode(
        call: MethodCall,
        result: Result,
    ) {
        val identifier = call.arguments as String
        wrapper.api
            .enableSDKMode(identifier)
            .subscribe({
                runOnUiThread { result.success(null) }
            }, {
                runOnUiThread {
                    result.error(it.toString(), it.message, null)
                }
            })
            .discard()
    }

    private fun disableSdkMode(
        call: MethodCall,
        result: Result,
    ) {
        val identifier = call.arguments as String
        wrapper.api
            .disableSDKMode(identifier)
            .subscribe({
                runOnUiThread { result.success(null) }
            }, {
                runOnUiThread {
                    result.error(it.toString(), it.message, null)
                }
            })
            .discard()
    }

    private fun isSdkModeEnabled(
        call: MethodCall,
        result: Result,
    ) {
        val identifier = call.arguments as String
        wrapper.api
            .isSDKModeEnabled(identifier)
            .subscribe({
                runOnUiThread { result.success(it) }
            }, {
                runOnUiThread {
                    result.error(it.toString(), it.message, null)
                }
            })
            .discard()
    }

    private fun doFirstTimeUse(
        call: MethodCall,
        result: Result,
    ) {
        val arguments = call.arguments as List<*>
        val identifier = arguments[0] as String
        val ftuConfig = gson.fromJson(arguments[1] as String, PolarFirstTimeUseConfig::class.java)

        wrapper.api
            .doFirstTimeUse(identifier, ftuConfig)
            .subscribe({
                runOnUiThread { result.success(null) }
            }, {
                runOnUiThread {
                    result.error(it.toString(), it.message, null)
                }
            })
            .discard()
    }

    private fun isFtuDone(
        call: MethodCall,
        result: Result,
    ) {
        val identifier = call.arguments as String

        wrapper.api
            .isFtuDone(identifier)
            .subscribe({ isFtuDone ->
                runOnUiThread { result.success(isFtuDone) }
            }, {
                runOnUiThread {
                    result.error(it.toString(), it.message, null)
                }
            })
            .discard()
    }
}

class PolarWrapper(
    context: Context,
    val api: PolarBleApi =
        PolarBleApiDefaultImpl.defaultImplementation(
            context,
            PolarBleSdkFeature.values().toSet(),
        ),
    private val sinks: MutableMap<Int, EventSink> = mutableMapOf(),
) : PolarBleApiCallbackProvider {
    init {
        api.setApiCallback(this)
    }

    fun addSink(
        id: Int,
        sink: EventSink,
    ) {
        sinks[id] = sink
    }

    fun removeSink(id: Int) {
        sinks.remove(id)
    }

    private fun success(
        event: String,
        data: Any?,
    ) {
        runOnUiThread { sinks.values.forEach { it.success(mapOf("event" to event, "data" to data)) } }
    }

    fun shutDown() {
        // Do not shutdown the api if other engines are still using it
        if (sinks.isNotEmpty()) return
        try {
            api.shutDown()
        } catch (e: Exception) {
            // This will throw if the API is already shut down
        }
    }

    override fun blePowerStateChanged(powered: Boolean) {
        success("blePowerStateChanged", powered)
    }

    override fun bleSdkFeatureReady(
        identifier: String,
        feature: PolarBleSdkFeature,
    ) {
        success("sdkFeatureReady", listOf(identifier, feature.name))
    }

    override fun bleSdkFeaturesReadiness(
        identifier: String,
        ready: List<PolarBleSdkFeature>,
        unavailable: List<PolarBleSdkFeature>,
    ) {
        success(
            "sdkFeaturesReadiness",
            listOf(
                identifier,
                ready.map { it.name },
                unavailable.map { it.name },
            ),
        )
    }

    override fun deviceConnected(polarDeviceInfo: PolarDeviceInfo) {
        success("deviceConnected", gson.toJson(polarDeviceInfo))
    }

    override fun deviceConnecting(polarDeviceInfo: PolarDeviceInfo) {
        success("deviceConnecting", gson.toJson(polarDeviceInfo))
    }

    override fun deviceDisconnected(polarDeviceInfo: PolarDeviceInfo) {
        success(
            "deviceDisconnected",
            // The second argument is the `pairingError` field on iOS
            // Since Android doesn't implement that, always send false
            listOf(gson.toJson(polarDeviceInfo), false),
        )
    }

    override fun disInformationReceived(
        identifier: String,
        uuid: UUID,
        value: String,
    ) {
        success("disInformationReceived", listOf(identifier, uuid.toString(), value))
    }

    override fun disInformationReceived(
        identifier: String,
        disInfo: DisInfo,
    ) {
        success("disInformationReceived", listOf(identifier, disInfo.key, disInfo.value))
    }

    override fun batteryLevelReceived(
        identifier: String,
        level: Int,
    ) {
        success("batteryLevelReceived", listOf(identifier, level))
    }

    override fun batteryChargingStatusReceived(
        identifier: String,
        chargingStatus: ChargeState,
    ) {
        success("batteryChargingStatusReceived", listOf(identifier, chargingStatus.name))
    }

    override fun htsNotificationReceived(
        identifier: String,
        data: PolarHealthThermometerData,
    ) {
        // Do nothing
    }

    override fun powerSourcesStateReceived(
        identifier: String,
        powerSourcesState: PowerSourcesState,
    ) {
        TODO("Not yet implemented")
    }

    @Deprecated("", replaceWith = ReplaceWith(""))
    override fun hrNotificationReceived(
        identifier: String,
        data: PolarHrData.PolarHrSample,
    ) {
        // Do nothing
    }
}

class StreamingChannel(
    messenger: BinaryMessenger,
    name: String,
    private val api: PolarBleApi,
    private val identifier: String,
    private val feature: PolarDeviceDataType,
    private val channel: EventChannel = EventChannel(messenger, name),
) : EventChannel.StreamHandler {
    private var subscription: Disposable? = null

    init {
        channel.setStreamHandler(this)
    }

    override fun onListen(
        arguments: Any?,
        events: EventSink,
    ) {
        // Will be null for some features
        val settings = gson.fromJson(arguments as String, PolarSensorSetting::class.java)

        val stream =
            when (feature) {
                PolarDeviceDataType.HR -> {
                    api.startHrStreaming(identifier)
                }

                PolarDeviceDataType.ECG -> {
                    api.startEcgStreaming(identifier, settings)
                }

                PolarDeviceDataType.ACC -> {
                    api.startAccStreaming(identifier, settings)
                }

                PolarDeviceDataType.PPG -> {
                    api.startPpgStreaming(identifier, settings)
                }

                PolarDeviceDataType.PPI -> {
                    api.startPpiStreaming(identifier)
                }

                PolarDeviceDataType.GYRO -> {
                    api.startGyroStreaming(identifier, settings)
                }

                PolarDeviceDataType.MAGNETOMETER -> {
                    api.startMagnetometerStreaming(
                        identifier,
                        settings,
                    )
                }

                PolarDeviceDataType.TEMPERATURE -> {
                    api.startTemperatureStreaming(
                        identifier,
                        settings,
                    )
                }

                PolarDeviceDataType.PRESSURE -> {
                    api.startPressureStreaming(identifier, settings)
                }

                PolarDeviceDataType.SKIN_TEMPERATURE -> {
                    api.startSkinTemperatureStreaming(identifier, settings)
                }

                PolarDeviceDataType.LOCATION -> {
                    api.startLocationStreaming(identifier, settings)
                }
            }

        subscription =
            stream.subscribe({
                runOnUiThread { events.success(gson.toJson(it)) }
            }, {
                runOnUiThread {
                    events.error(it.toString(), it.message, null)
                }
            }, {
                runOnUiThread { events.endOfStream() }
            })
    }

    override fun onCancel(arguments: Any?) {
        subscription?.dispose()
    }

    fun dispose() {
        subscription?.dispose()
        channel.setStreamHandler(null)
    }
}
