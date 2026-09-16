class SoundController {
  bool isLocked = false;

  void lock() {
    isLocked = true;
  }

  void unlock() {
    isLocked = false;
  }
}
