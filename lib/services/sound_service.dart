import 'package:audioplayers/audioplayers.dart';

/// Centralized sound service with pre-loaded audio for near-zero latency.
/// All sounds are loaded into Android SoundPool at app startup via setSource().
/// Replay uses resume() — a single platform channel call, no file I/O.
class SoundService {
  static final SoundService _instance = SoundService._internal();
  factory SoundService() => _instance;
  SoundService._internal();

  bool _initialized = false;

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
      final players = [_correctPlayer, _wrongPlayer, _startPlayer, _readyPlayer, _endingPlayer];

      // Set all to low-latency mode (uses Android SoundPool internally)
      for (final p in players) {
        await p.setPlayerMode(PlayerMode.lowLatency);
        await p.setReleaseMode(ReleaseMode.stop);
      }

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
    if (!_initialized) return;
    player.stop().then((_) => player.resume());
  }

  // ─── Looping sounds (for results screen BGM) ───

  Future<void> playEndingSoundLoop() async {
    if (!_initialized) return;
    await _endingPlayer.stop();
    await _endingPlayer.setReleaseMode(ReleaseMode.loop);
    await _endingPlayer.seek(Duration.zero);
    await _endingPlayer.resume();
  }

  Future<void> stopEndingSound() async {
    await _endingPlayer.stop();
    await _endingPlayer.setReleaseMode(ReleaseMode.stop);
  }

  void dispose() {
    for (final p in [_correctPlayer, _wrongPlayer, _startPlayer, _readyPlayer, _endingPlayer]) {
      p.dispose();
    }
    _initialized = false;
  }
}
