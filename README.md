# UniAccess (ADAPT) — AI Accessibility Assistant for Visually Impaired Users

**UniAccess** is an offline-first accessibility assistant built in Flutter for visually impaired users. It provides advanced computer vision, document reading, and voice interaction—operated entirely using **hardware volume buttons** and the **proximity sensor** so users never need to touch the screen after opening the application.

---

## 🌟 Key Features

### 1. Hands-Free Hardware Navigation
Operated completely using physical device buttons and proximity gestures:
- **Volume Up / Quick Wave**: Cycle application modes (*Sight Mode*, *Sound Mode*, *Motion Mode*).
- **Volume Down / Sensor Hover (≥1.5s)**: Lock selected mode or unlock back to navigation.
- **Volume Up (Locked Sight Mode)**: Cycle Sight tools (*Item Scanner*, *Document Reader*, *Torch Light*).
- **Volume Down Single Click**: Execute selected Sight tool.
- **Volume Down Long Press (≥800ms)**: Start voice question follow-up.
- **Volume Down Double Click (<500ms)**: Unlock Sight Mode.
- **Hold Volume Up (3s)**: Toggle custom hardware interception to allow standard phone media volume.

---

### 2. Hybrid Vision Architecture (Item Scanner)
Combines **On-Device Google ML Kit** with **Cloud Gemini 3.6 Flash** for optimal performance, offline capabilities, and deep visual reasoning:

```
                      USER (Volume Down)
                               │
                         CAMERA CAPTURE
                               │
                    _lastScannedImageBytes
                               │
            GOOGLE ML KIT — ON-DEVICE PROCESSING
            ├── Object Detection (labels & bounds)
            ├── Text Recognition (OCR)
            └── Image Labeling (scene tags)
                               │
                     DECISION / INTENT ENGINE
                               │
       ┌───────────────────────┴───────────────────────┐
       │                                               │
 SIMPLE TASK / QUESTION                       COMPLEX VISUAL TASK
 (Presence check, text read)                  (Scene description, colors,
       │                                       spatial reasoning, brands)
       ↓                                               │
 On-Device Resolution                                  ↓
 (0 API Calls / 0s Latency)                   Gemini 3.6 Flash Request
       │                                      (Image + ML Kit Context)
       │                                               │
       └───────────────────────┬───────────────────────┘
                               │
                      _fullGeminiResponse
                               │
                              TTS (Complete Audio)
                               │
                      UI (Shortened Preview)
```

- **On-Device ML Kit**: Detects objects, recognizes text, and tags scene categories offline.
- **Simple On-Device Queries**: Presence checks (*"Is there a laptop?"*) or text reading (*"Read text"*) are resolved locally without network calls.
- **Gemini 3.6 Flash**: Provides deep natural-language scene descriptions and handles complex visual questions (spatial layout, colors, brands, screen text, visual reasoning).
- **Hybrid Context**: ML Kit detections are passed as supporting context to Gemini, while the captured image remains the ultimate source of truth.
- **Follow-up Memory**: Voice follow-ups reuse the original stored image bytes (`_lastScannedImageBytes`) without re-capturing a new photo.

---

### 3. Decoupled Audio & UI Architecture
- **Complete Spoken Response**: The spoken Text-To-Speech engine receives the **full, untruncated** Gemini response (`_fullGeminiResponse`). Long responses are automatically split into natural sentence chunks and spoken sequentially using `awaitSpeakCompletion(true)` to prevent Android TTS cutoffs.
- **Shortened UI Preview**: The screen status card displays a shortened preview string (truncated at 300 characters with `...`) without affecting audio playback.

---

### 4. Resilient Gemini Networking Layer
- **Bounded Exponential Backoff**: Retries transient errors (HTTP `429`, `408`, `500`, `502`, `503`, `504` and network socket timeouts) up to 5 attempts with delays (~1s, ~2s, ~4s, ~8s, ~16s + random 0–300ms jitter).
- **Header Inspection**: Respects `Retry-After` HTTP headers.
- **Immediate Failure Handling**: Non-retryable client errors (`400`, `401`, `403`, `404`) return user-friendly explanatory status messages without looping.
- **API Key Security**: API keys are masked in debug logs and never exposed in error text or URLs.

---

## 🛠 Project Structure

```
lib/
├── main.dart                             # Clean app entrypoint
├── core/
│   ├── constants/
│   │   ├── gemini_prompts.dart          # Scene, document, intent, and follow-up prompts
│   │   ├── hardware_channels.dart       # Platform method & event channel names
│   │   └── permissions.dart             # Camera and microphone permissions
│   ├── models/
│   │   ├── conversation_turn.dart       # Gemini turn model
│   │   └── ai_intent.dart               # Spoken question intent classifier
│   └── services/
│       ├── gemini_service.dart          # Gemini API client, retries, and conversation state
│       ├── ml_kit_service.dart          # On-device Google ML Kit vision processor
│       ├── camera_service.dart          # Camera initialization, capture, image stream
│       ├── tts_service.dart             # Sequential chunked Text-To-Speech engine
│       ├── speech_service.dart          # Speech-To-Text engine & silence detection
│       ├── torch_service.dart           # Flashlight flashlight controller
│       ├── hardware_button_service.dart # Volume button events & long/double press timers
│       └── proximity_service.dart       # Proximity wave & hover sensor listener
├── features/
│   ├── sight/
│   │   ├── sight_controller.dart        # Sight tools, decision engine, & guidance stream
│   │   └── widgets/
│   │       ├── camera_preview_widget.dart # Camera preview overlay with mic/torch badges
│   │       └── status_card.dart          # Unified status display card
│   ├── sound/
│   │   └── sound_controller.dart        # Sound mode state controller
│   └── motion/
│       └── motion_controller.dart       # Motion mode state controller
└── screens/
    └── home_screen.dart                 # Primary UI screen
```

---

## 🚀 Getting Started

### Prerequisites
- Flutter SDK `^3.13.0` or higher
- Android SDK (API Level 21+)
- Connected Android Device or Emulator

### Installation & Run

1. **Clone the repository**:
   ```bash
   git clone https://github.com/murtydsk-design/ADAPT.git
   cd ADAPT
   ```

2. **Get dependencies**:
   ```bash
   flutter pub get
   ```

3. **Run tests & analysis**:
   ```bash
   flutter analyze
   flutter test
   ```

4. **Run on Android**:
   ```bash
   flutter run
   ```

5. **Providing a Custom Gemini API Key** *(Optional)*:
   Pass your Google AI Studio API key at build time:
   ```bash
   flutter run --dart-define=GEMINI_API_KEY=YOUR_GEMINI_API_KEY
   ```
   Or set `_defaultApiKey` in `lib/core/services/gemini_service.dart`.

---

## 📜 License
This project is developed for accessibility research and assistive technology applications.
