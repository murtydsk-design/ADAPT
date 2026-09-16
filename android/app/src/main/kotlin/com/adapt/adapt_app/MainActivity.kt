package com.adapt.adapt_app

import android.content.Context
import android.media.AudioManager
import android.view.KeyEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val BUTTON_CHANNEL = "com.adapt/hardware_buttons"
    private val SWITCH_CHANNEL = "com.adapt/hardware_switch"
    private var eventSink: EventChannel.EventSink? = null

    private var isCustomMode = true
    private lateinit var audioManager: AudioManager

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, BUTTON_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }
                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SWITCH_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "setInterception") {
                    isCustomMode = call.argument<Boolean>("intercept") ?: true
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
    }

    // This is the Master Front Gate! It catches the button before Realme UI does.
    // This is the Master Front Gate!
    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        val keyCode = event.keyCode

        if (keyCode == KeyEvent.KEYCODE_VOLUME_UP || keyCode == KeyEvent.KEYCODE_VOLUME_DOWN) {

            if (event.action == KeyEvent.ACTION_DOWN) {
                // repeatCount == 0 means this code ONLY runs once, even if held down!
                if (event.repeatCount == 0) {
                    when (keyCode) {
                        KeyEvent.KEYCODE_VOLUME_UP -> eventSink?.success("UP_PRESSED")
                        KeyEvent.KEYCODE_VOLUME_DOWN -> eventSink?.success("DOWN_PRESSED")
                    }

                    // We moved the volume change INSIDE this block.
                    // Now, holding the button won't blast the volume to 100%!
                    // We moved the volume change INSIDE this block.
                    if (!isCustomMode) {
                        val currentVol = audioManager.getStreamVolume(AudioManager.STREAM_MUSIC)
                        val maxVol = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                        var newVol = currentVol

                        if (keyCode == KeyEvent.KEYCODE_VOLUME_UP && currentVol < maxVol) {
                            newVol += 1
                        } else if (keyCode == KeyEvent.KEYCODE_VOLUME_DOWN && currentVol > 0) {
                            newVol -= 1
                        }

                        // THIS IS THE CHANGED LINE: We replaced '0' with 'AudioManager.FLAG_SHOW_UI'
                        audioManager.setStreamVolume(AudioManager.STREAM_MUSIC, newVol, AudioManager.FLAG_SHOW_UI)
                    }
                }
            }
            else if (event.action == KeyEvent.ACTION_UP) {
                when (keyCode) {
                    KeyEvent.KEYCODE_VOLUME_UP -> eventSink?.success("UP_RELEASED")
                    KeyEvent.KEYCODE_VOLUME_DOWN -> eventSink?.success("DOWN_RELEASED")
                }
            }

            return true
        }

        return super.dispatchKeyEvent(event)
    }
}
