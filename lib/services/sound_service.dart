import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Centralized sound service with pre-loaded audio for near-zero latency.
/// All sounds are loaded into Android SoundPool at app startup via setSource().
/// Replay uses resume() — a single platform channel call, no file I/O.
class SoundService {
  static final SoundService _instance = SoundService._internal();
  factory SoundService() => _instance;
  SoundService._internal();

  bool _initialized = false;
  bool _isMuted = false;
  static const String _mutePrefsKey = 'mute_all_sounds';

  // Dedicated player per sound — each pre-loaded into SoundPool memory
  final AudioPlayer _correctPlayer = AudioPlayer();
  final AudioPlayer _wrongPlayer = AudioPlayer();
  final AudioPlayer _startPlayer = AudioPlayer();
  final AudioPlayer _readyPlayer = AudioPlayer();
  final AudioPlayer _endingPlayer = AudioPlayer();

  /// Pre-load all sounds at app startup for instant playback later.
  Future<void> init() async {
    if (_initialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _isMuted = prefs.getBool(_mutePrefsKey) ?? false;

      final sfxPlayers = [_correctPlayer, _wrongPlayer, _startPlayer, _readyPlayer];

      // Set all to low-latency mode (uses Android SoundPool internally)
      for (final p in sfxPlayers) {
        await p.setPlayerMode(PlayerMode.lowLatency);
        await p.setReleaseMode(ReleaseMode.stop);
      }

      // Use media player mode for long looped result audio for smoother loop points.
      await _endingPlayer.setPlayerMode(PlayerMode.mediaPlayer);
      await _endingPlayer.setReleaseMode(ReleaseMode.stop);

      // Pre-load audio data into SoundPool memory
      await Future.wait([
        _correctPlayer.setSource(AssetSource('images/correctanswer.aac')),
        _wrongPlayer.setSource(AssetSource('images/wronganswer.aac')),
        _startPlayer.setSource(AssetSource('images/startquiz.aac')),
        _readyPlayer.setSource(AssetSource('images/quizready.aac')),
        _endingPlayer.setSource(AssetSource('images/endingsound.aac')),
      ]);

      _initialized = true;
    } catch (_) {
      // Silently fail — sounds are non-critical
    }
  }

  // ─── One-shot sounds (instant fire-and-forget) ───

  void playStartQuiz() => _replay(_startPlayer);

  void playCorrectAnswer() => _replay(_correctPlayer);

  void playWrongAnswer() => _replay(_wrongPlayer);

  void playQuizReady() => _replay(_readyPlayer);

  /// Replay a pre-loaded sound instantly.
  /// stop() resets the stream, resume() fires a new SoundPool.play().
  void _replay(AudioPlayer player) {
    if (!_initialized || _isMuted) return;
    player.stop().then((_) => player.resume());
  }

  // ─── Looping sounds (for results screen BGM) ───

  Future<void> playEndingSoundLoop() async {
    if (!_initialized || _isMuted) return;
    await _endingPlayer.stop();
    await _endingPlayer.setReleaseMode(ReleaseMode.loop);
    await _endingPlayer.resume();
  }

  Future<void> stopEndingSound() async {
    await _endingPlayer.stop();
    await _endingPlayer.setReleaseMode(ReleaseMode.stop);
  }

  bool get isMuted => _isMuted;

  Future<void> setMuted(bool muted) async {
    _isMuted = muted;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_mutePrefsKey, muted);

    if (muted) {
      await stopEndingSound();
    }
  }

  void dispose() {
    for (final p in [_correctPlayer, _wrongPlayer, _startPlayer, _readyPlayer, _endingPlayer]) {
      p.dispose();
    }
    _initialized = false;
  }
}
