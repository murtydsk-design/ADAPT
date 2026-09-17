import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration/vibration.dart';

import '../core/constants/permissions.dart';
import '../core/services/camera_service.dart';
import '../core/services/hardware_button_service.dart';
import '../core/services/openai_service.dart';
import '../core/services/proximity_service.dart';
import '../core/services/speech_service.dart';
import '../core/services/torch_service.dart';
import '../core/services/tts_service.dart';
import '../features/motion/motion_controller.dart';
import '../features/sight/sight_controller.dart';
import '../features/sight/widgets/camera_preview_widget.dart';
import '../features/sight/widgets/status_card.dart';
import '../features/sound/sound_controller.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Services
  late final TtsService _ttsService;
  late final SpeechService _speechService;
  late final CameraService _cameraService;
  late final TorchService _torchService;
  late final OpenAiService _openAiService;
  late final HardwareButtonService _hardwareButtonService;
  late final ProximityService _proximityService;

  // Controllers
  late final SightController _sightController;
  late final SoundController _soundController;
  late final MotionController _motionController;

  int _activeModeIndex = 0;
  final List<String> _modes = ["Sight Mode", "Sound Mode", "Motion Mode"];
  bool _isModeLocked = false;
  String _activeActionStatus = "Initializing...";

  @override
  void initState() {
    super.initState();
    _initServicesAndControllers();
  }

  void _initServicesAndControllers() {
    _ttsService = TtsService();
    _speechService = SpeechService();
    _cameraService = CameraService();
    _torchService = TorchService();
    _openAiService = OpenAiService();
    _hardwareButtonService = HardwareButtonService();
    _proximityService = ProximityService();

    _sightController = SightController(
      cameraService: _cameraService,
      openAiService: _openAiService,
      torchService: _torchService,
      speechService: _speechService,
      ttsService: _ttsService,
    );
    _soundController = SoundController();
    _motionController = MotionController();

    _initializeApp();
  }

  Future<void> _initializeApp() async {
    await AppPermissions.requestAll();
    await _ttsService.init();

    await _speechService.init(
      onError: (err) {
        _sightController.cancelVoiceQuestion(onStateChanged: _updateState);
      },
      onDone: () {
        _sightController.finalizeVoiceQuestion(onStateChanged: _updateState);
      },
    );

    await _loadSavedState();
    _setupHardwareInteractions();
  }

  void _updateState() {
    if (mounted) {
      setState(() {
        if (_isModeLocked && _activeModeIndex == 0) {
          _activeActionStatus = _sightController.activeActionStatus;
        }
      });
    }
  }

  Future<void> _loadSavedState() async {
    final prefs = await SharedPreferences.getInstance();
    final savedMode = prefs.getInt('saved_mode_index') ?? 0;

    setState(() {
      _activeModeIndex = savedMode;
      _isModeLocked = false;
      _activeActionStatus = "Navigation: ${_modes[_activeModeIndex]}";
    });

    _ttsService.speak(_modes[_activeModeIndex]);
  }

  Future<void> _saveState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('saved_mode_index', _activeModeIndex);
  }

  void _setupHardwareInteractions() {
    _proximityService.startListening(
      onQuickWave: () {
        if (!_hardwareButtonService.isMediaVolumeUnlocked && !_isModeLocked) {
          _cycleToNextMode(triggeredByWave: true);
        }
      },
      onLongHover: () {
        if (_hardwareButtonService.isMediaVolumeUnlocked) return;
        if (_isModeLocked) {
          _unlockMode();
        } else {
          _lockMode();
        }
      },
    );

    _hardwareButtonService.startListening(
      onVolumeUpRelease: () {
        if (!_isModeLocked) {
          _cycleToNextMode(triggeredByWave: false);
        } else if (_activeModeIndex == 0) {
          _sightController.cycleSightTool(onStateChanged: _updateState);
        }
      },
      onVolumeDownSingleClick: () {
        if (!_isModeLocked) {
          _lockMode();
        } else if (_activeModeIndex == 0 && !_sightController.isListeningSpeech) {
          _sightController.executeSightToolAction(onStateChanged: _updateState);
        }
      },
      onVolumeDownLongPress: () {
        if (_isModeLocked && _activeModeIndex == 0) {
          _sightController.startVoiceQuestionCapture(onStateChanged: _updateState);
        }
      },
      onVolumeDownDoubleClick: () {
        if (_isModeLocked) {
          _unlockMode();
        }
      },
      onMediaVolumeToggle: (isUnlocked) {
        _handleMediaVolumeToggle(isUnlocked);
      },
    );
  }

  void _cycleToNextMode({required bool triggeredByWave}) {
    setState(() {
      _activeModeIndex = (_activeModeIndex + 1) % _modes.length;
      _activeActionStatus = triggeredByWave
          ? "Wave: ${_modes[_activeModeIndex]}"
          : "Click: ${_modes[_activeModeIndex]}";
    });

    _saveState();
    Vibration.vibrate(duration: 80);
    _ttsService.speak(_modes[_activeModeIndex]);
  }

  void _lockMode() async {
    if (_isModeLocked) return;

    setState(() {
      _isModeLocked = true;
    });

    Vibration.vibrate(duration: 250);

    if (_activeModeIndex == 0) {
      await _sightController.lockMode(onStateChanged: _updateState);
      setState(() {
        _activeActionStatus = _sightController.activeActionStatus;
      });
    } else if (_activeModeIndex == 1) {
      _soundController.lock();
      setState(() {
        _activeActionStatus = "Sound Mode Active (Locked)";
      });
      _ttsService.speak("Sound mode locked. Listening.");
    } else if (_activeModeIndex == 2) {
      _motionController.lock();
      setState(() {
        _activeActionStatus = "Motion Mode Active (Locked)";
      });
      _ttsService.speak("Motion mode locked. Tracking gestures.");
    }
  }

  void _unlockMode() async {
    if (!_isModeLocked) return;

    if (_activeModeIndex == 0) {
      await _sightController.unlockMode(onStateChanged: _updateState);
    } else if (_activeModeIndex == 1) {
      _soundController.unlock();
    } else if (_activeModeIndex == 2) {
      _motionController.unlock();
    }

    setState(() {
      _isModeLocked = false;
      _activeActionStatus = "Unlocked: Navigating ${_modes[_activeModeIndex]}";
    });

    Vibration.vibrate(duration: 100);
    _ttsService.speak("Mode unlocked. Navigating ${_modes[_activeModeIndex]}");
  }

  void _handleMediaVolumeToggle(bool isUnlocked) {
    if (isUnlocked) {
      Vibration.vibrate(duration: 200);
      _ttsService.speak("Media volume mode on");
      setState(() {
        _activeActionStatus = "Media volume mode active";
      });
    } else {
      Vibration.vibrate(duration: 500);
      _ttsService.speak("Custom app mode locked");
      setState(() {
        _activeActionStatus = _isModeLocked
            ? "${_modes[_activeModeIndex]} Active"
            : "Navigation: ${_modes[_activeModeIndex]}";
      });
    }
  }

  Color _getModeColor() {
    if (_hardwareButtonService.isMediaVolumeUnlocked) {
      return Colors.grey;
    }

    if (_sightController.isListeningSpeech) {
      return Colors.deepOrange;
    }

    switch (_activeModeIndex) {
      case 0:
        return _sightController.isProcessingAi
            ? Colors.deepPurple
            : Colors.indigo;
      case 1:
        return Colors.teal;
      case 2:
        return Colors.deepOrange;
      default:
        return Colors.blue;
    }
  }

  @override
  void dispose() {
    _ttsService.stop();
    _speechService.cancel();
    _proximityService.stopListening();
    _hardwareButtonService.dispose();
    _cameraService.disposeCamera();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeColor = _getModeColor();

    return Scaffold(
      appBar: AppBar(
        title: const Text('UniAccess Vision & Smart Reader'),
        backgroundColor: activeColor,
      ),
      body: Column(
        children: [
          if (_isModeLocked &&
              _activeModeIndex == 0 &&
              _cameraService.controller != null &&
              _cameraService.isInitialized)
            Expanded(
              flex: 3,
              child: CameraPreviewWidget(
                cameraController: _cameraService.controller!,
                isListeningSpeech: _sightController.isListeningSpeech,
                isProcessingAi: _sightController.isProcessingAi,
                isTorchOn: _torchService.isTorchOn,
              ),
            )
          else
            Expanded(
              flex: 2,
              child: Center(
                child: Icon(
                  _isModeLocked ? Icons.lock : Icons.lock_open,
                  size: 80,
                  color: activeColor,
                ),
              ),
            ),
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _hardwareButtonService.isMediaVolumeUnlocked
                        ? "MEDIA VOLUME MODE"
                        : (_isModeLocked
                                ? "SIGHT: ${_sightController.currentToolName}"
                                : _modes[_activeModeIndex])
                            .toUpperCase(),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                      color: activeColor,
                    ),
                  ),
                  const SizedBox(height: 10),
                  StatusCard(
                    statusText: _activeActionStatus,
                    activeColor: activeColor,
                  ),
                  const SizedBox(height: 12),
                  if (_isModeLocked && _activeModeIndex == 0)
                    Text(
                      _sightController.sightToolIndex == 1
                          ? "• Live guidance on | Hold still when detected\n• Vol Down: Read full document | • Double Click: Unlock"
                          : "• Click Vol Down: Scan Full Scene | • Hold Vol Down: Ask Follow-up\n• Vol Up: Switch Tool | • Double Click Vol Down: Unlock",
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black87,
                      ),
                    )
                  else
                    const Text(
                      "• Vol Up / Wave: Next Mode\n• Vol Down / Sensor Hover (≥1.5s): Lock Mode",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.black87,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
