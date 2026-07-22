/// 小说阅读器 TTS 朗读控制器（P3.1）。
///
/// 封装 flutter_tts，提供逐段朗读、暂停/恢复/停止、自动翻段功能。
/// 朗读状态通过 [notifyListeners] 广播，阅读器据此更新 UI。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

enum NovelTtsState {
  stopped,
  playing,
  paused,
}

class NovelTtsController extends ChangeNotifier {
  NovelTtsController();

  FlutterTts? _tts;
  NovelTtsState _state = NovelTtsState.stopped;
  int _currentIndex = 0;
  List<String> _paragraphs = const <String>[];

  double _rate = 1.0;
  Timer? _sleepTimer;
  Duration? _sleepRemaining;
  bool _backgroundMode = false;

  NovelTtsState get state => _state;
  int get currentIndex => _currentIndex;
  bool get isPlaying => _state == NovelTtsState.playing;
  bool get isPaused => _state == NovelTtsState.paused;
  double get rate => _rate;
  Duration? get sleepRemaining => _sleepRemaining;
  bool get hasSleepTimer => _sleepTimer != null;
  bool get backgroundMode => _backgroundMode;

  /// 设置后台朗读开关：true 时应用进入后台仍继续朗读；
  /// false 时进入后台由调用方（AppLifecycle 监听）触发 [pause]。
  void setBackground(bool enabled) {
    if (_backgroundMode == enabled) return;
    _backgroundMode = enabled;
    notifyListeners();
  }

  /// 初始化 TTS 引擎（懒加载）。
  Future<void> _ensureTts() async {
    if (_tts != null) return;
    _tts = FlutterTts();
    await _tts!.setLanguage('zh-CN');
    await _tts!.setSpeechRate(_rate);
    _tts!.setCompletionHandler(_onComplete);
  }

  /// 开始朗读段落列表，从指定索引开始。
  ///
  /// [sleepTimer] 为睡眠定时（分钟）；> 0 时启动后自动开启定时器，
  /// 到时停止朗读。用于 prefs.ttsSleepTimer 持久化恢复。
  Future<void> speak(List<String> paragraphs,
      {int startIndex = 0, int sleepTimer = 0}) async {
    await _ensureTts();
    _paragraphs = paragraphs;
    _currentIndex = startIndex;
    _state = NovelTtsState.playing;
    notifyListeners();
    await _setAwake(true);
    if (sleepTimer > 0) {
      startSleepTimer(sleepTimer);
    }
    await _speakCurrent();
  }

  /// 朗读当前段落。
  Future<void> _speakCurrent() async {
    if (_tts == null ||
        _currentIndex < 0 ||
        _currentIndex >= _paragraphs.length) {
      _state = NovelTtsState.stopped;
      notifyListeners();
      return;
    }
    await _tts!.speak(_paragraphs[_currentIndex]);
  }

  /// 暂停朗读。
  Future<void> pause() async {
    if (_tts == null || _state != NovelTtsState.playing) return;
    await _tts!.pause();
    _state = NovelTtsState.paused;
    notifyListeners();
  }

  /// 恢复朗读。
  Future<void> resume() async {
    if (_tts == null || _state != NovelTtsState.paused) return;
    _state = NovelTtsState.playing;
    notifyListeners();
    await _setAwake(true);
    await _speakCurrent();
  }

  /// 停止朗读。
  Future<void> stop() async {
    if (_tts == null) return;
    await _tts!.stop();
    _state = NovelTtsState.stopped;
    _cancelSleepTimer();
    _sleepRemaining = null;
    await _setAwake(false);
    notifyListeners();
  }

  /// 朗读下一段。
  Future<void> next() async {
    if (_currentIndex < _paragraphs.length - 1) {
      _currentIndex++;
      _state = NovelTtsState.playing;
      notifyListeners();
      await _speakCurrent();
    }
  }

  /// 朗读上一段。
  Future<void> prev() async {
    if (_currentIndex > 0) {
      _currentIndex--;
      _state = NovelTtsState.playing;
      notifyListeners();
      await _speakCurrent();
    }
  }

  /// 设置语速（0.5–2.0）。
  Future<void> setRate(double rate) async {
    _rate = rate.clamp(0.5, 2.0);
    await _ensureTts();
    await _tts!.setSpeechRate(_rate);
    notifyListeners();
  }

  /// 启动睡眠定时（分钟；<=0 取消）。到时自动停止朗读。
  void startSleepTimer(int minutes) {
    _cancelSleepTimer();
    if (minutes <= 0) {
      _sleepRemaining = null;
      notifyListeners();
      return;
    }
    _sleepRemaining = Duration(minutes: minutes);
    _sleepTimer = Timer.periodic(const Duration(seconds: 1), (Timer t) {
      final left =
          (_sleepRemaining ?? Duration.zero) - const Duration(seconds: 1);
      if (left <= Duration.zero) {
        _sleepRemaining = null;
        _cancelSleepTimer();
        stop();
      } else {
        _sleepRemaining = left;
        notifyListeners();
      }
    });
    notifyListeners();
  }

  /// 取消睡眠定时。
  void cancelSleepTimer() {
    _sleepRemaining = null;
    _cancelSleepTimer();
    notifyListeners();
  }

  void _cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
  }

  /// 后台保活：朗读时持有唤醒锁，停止时释放（熄屏 / 退后台仍可继续朗读）。
  Future<void> _setAwake(bool on) async {
    try {
      if (on) {
        await WakelockPlus.enable();
      } else {
        await WakelockPlus.disable();
      }
    } on Object {
      // 部分平台不支持唤醒锁，忽略。
    }
  }

  /// 当前段落朗读完毕回调：自动朗读下一段。
  void _onComplete() {
    if (_state == NovelTtsState.playing &&
        _currentIndex < _paragraphs.length - 1) {
      _currentIndex++;
      notifyListeners();
      _speakCurrent();
    } else {
      _state = NovelTtsState.stopped;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _cancelSleepTimer();
    _tts?.stop();
    try {
      WakelockPlus.disable();
    } on Object {
      // 忽略
    }
    super.dispose();
  }
}
