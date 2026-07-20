import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// 안드로이드에서 쓸 Google TTS 엔진 패키지 이름.
const String _googleTtsEngine = 'com.google.android.tts';

/// 말하기 속도. 1.0이 그 음성의 보통 속도다.
///
/// 웹에서는 이 값이 `utterance.rate`로 그대로 들어간다. 예전에 쓰던 0.5는
/// 절반 속도라 늘어지게 들렸다.
///
/// TTS를 쓰는 화면이 여럿이라 여기 한 곳에 둔다. 화면마다 따로 적어 두면
/// 한쪽만 고쳐져 화면에 따라 말 속도가 달라진다.
const double kSpeechRate = 1.0;

/// 안드로이드의 음성 합성 엔진을 Google TTS로 바꾼다.
///
/// 기기에 따라 삼성 등 제조사 엔진이 기본으로 잡혀 있어 목소리가 달라진다.
/// 엔진 지정은 안드로이드에만 있는 기능이라 다른 플랫폼에서는 조용히 넘어간다.
/// Google TTS가 설치돼 있지 않으면 기본 엔진을 그대로 둔다.
Future<void> applyGoogleTtsEngine(FlutterTts tts) async {
  // 안드로이드 전용 기능이다. 다른 플랫폼에서 부르면 플러그인이 예외를 던지거나
  // 응답하지 않을 수 있어, 아예 건드리지 않는다.
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;

  try {
    final dynamic raw = await tts.getEngines;
    if (raw is! List) return;

    final engines = raw.map((e) => e.toString()).toList();
    if (!engines.contains(_googleTtsEngine)) {
      debugPrint('[MimicBot.tts] Google TTS 엔진이 없습니다. 설치된 엔진: $engines');
      return;
    }

    await tts.setEngine(_googleTtsEngine);
  } catch (_) {
    // 안드로이드가 아니거나 엔진 조회에 실패하면 기본 엔진을 유지한다.
  }
}

/// 한국어 음성 목록을 읽는다. 비어 있으면 잠시 기다렸다 다시 시도한다.
///
/// 브라우저는 음성 목록을 비동기로 채우기 때문에, 페이지를 연 직후 물어보면
/// 빈 목록이 돌아오는 일이 흔하다. 그대로 포기하면 Google 음성을 골라 보지도 못하고
/// 기본 음성으로 말하게 된다.
Future<List<Map<String, String>>> _loadKoreanVoices(FlutterTts tts) async {
  const attempts = 5;
  const gap = Duration(milliseconds: 300);

  for (var attempt = 0; attempt < attempts; attempt++) {
    final dynamic raw = await tts.getVoices;

    if (raw is List) {
      final korean = raw
          .whereType<Map>()
          .map((m) => m.map(
              (k, v) => MapEntry(k.toString(), (v ?? '').toString())))
          .where((v) => (v['locale'] ?? '').toLowerCase().startsWith('ko'))
          .toList();

      if (korean.isNotEmpty) return korean;
    }

    if (attempt < attempts - 1) await Future<void>.delayed(gap);
  }

  return const [];
}

/// 사용 가능한 음성 목록에서 한국어 Google 여성 음성을 골라 [tts]에 설정한다.
///
/// 음성 이름은 플랫폼마다 다르다.
/// - Chrome: `Google 한국의` — 브라우저가 제공하는 Google 음성
/// - 안드로이드: `ko-kr-x-ism#female_1` 같은 이름 (Google TTS 엔진이 제공)
/// - Windows: `Microsoft Heami`, `Microsoft SunHi` — Google 음성이 없다
///
/// 그래서 Google 음성을 가장 높게 치되, 없으면 그다음으로 자연스러운 것을 고른다.
/// 실패하면 기본 음성을 그대로 둔다.
Future<void> applyKoreanFemaleVoice(FlutterTts tts) async {
  final ordered = await koreanVoicesByPreference(tts);
  if (ordered.isEmpty) return;
  await _setVoice(tts, ordered.first);
}

/// 고른 음성을 실제로 적용한다.
Future<void> _setVoice(FlutterTts tts, Map<String, String> voice) async {
  await tts.setVoice({
    'name': voice['name'] ?? '',
    'locale': voice['locale'] ?? 'ko-KR',
  });
  debugPrint('[MimicBot.tts] 음성 적용: ${voice['name']} (${voice['locale']})');
}

/// 한국어 음성을 선호 순서대로 돌려준다. 앞에 있을수록 먼저 써 본다.
Future<List<Map<String, String>>> koreanVoicesByPreference(
    FlutterTts tts) async {
  try {
    final korean = await _loadKoreanVoices(tts);
    if (korean.isEmpty) {
      debugPrint('[MimicBot.tts] 한국어 음성을 찾지 못해 기본 음성을 씁니다.');
      return const [];
    }

    bool isFemale(String name, String gender) {
      if (gender.isNotEmpty) {
        return gender.startsWith('f') || gender.contains('female');
      }
      const femaleHints = ['female', 'heami', 'sunhi', 'woman', 'yuna', 'nari'];
      const maleHints = ['male', 'injoon', 'man'];
      if (maleHints.any(name.contains)) return false;
      return femaleHints.any(name.contains);
    }

    // 점수: Google 음성 > 신경망 > 여성 > 비-Desktop.
    //
    // Google 음성 가중치를 가장 크게 둬서, 다른 항목을 모두 만족하는 음성이 있어도
    // Google 음성이 있으면 그쪽이 뽑히게 한다.
    int score(Map<String, String> v) {
      final name = (v['name'] ?? '').toLowerCase();
      final gender = (v['gender'] ?? '').toLowerCase();
      var s = 0;
      if (name.contains('google')) s += 32;
      const naturalHints = ['natural', 'neural', 'online'];
      if (naturalHints.any(name.contains)) s += 8;
      if (isFemale(name, gender)) s += 4;
      if (!name.contains('desktop')) s += 2; // OneCore/모바일 음성이 더 자연스러움
      return s;
    }

    korean.sort((a, b) => score(b).compareTo(score(a)));

    // 웹에서는 name과 locale만 알 수 있어(성별·로컬 여부는 안 옴) 이름으로 판단한다.
    debugPrint('[MimicBot.tts] 한국어 음성 후보(선호순): '
        '${korean.map((v) => v['name']).join(' | ')}');

    return korean;
  } catch (_) {
    // 음성 조회 실패 시 기본 음성 유지.
    return const [];
  }
}

/// 한국어 여성 TTS 재생용 경량 서비스.
/// 각 화면에서 인스턴스를 만들어 인사말 등을 말할 때 사용한다.
class TtsService {
  /// 고른 음성이 소리를 내기 시작할 때까지 기다려 볼 시간.
  ///
  /// 이 안에 시작하지 않으면 그 음성은 소리가 안 나는 것으로 보고 다음 후보로 넘어간다.
  /// 브라우저는 소리를 못 내도 오류를 주지 않고 조용히 넘어가는 일이 많아,
  /// 시작 신호가 오는지로 판단할 수밖에 없다.
  static const Duration _startTimeout = Duration(milliseconds: 1500);

  /// 목소리 높낮이. 1.0이 그 음성의 기본값이다.
  static const double _pitch = 1.0;

  final FlutterTts _tts = FlutterTts();
  bool _ready = false;
  bool _speaking = false;

  /// 선호 순서대로 정렬된 한국어 음성 후보.
  List<Map<String, String>> _voices = const [];

  /// 지금 쓰고 있는 후보의 위치.
  int _voiceIndex = 0;

  /// 발화가 시작되면 완료되는 신호. 시작 여부를 기다리는 데 쓴다.
  Completer<void>? _started;

  Future<void> _ensure() async {
    if (_ready) return;
    _ready = true; // 준비 중 다시 불려도 두 번 설정하지 않는다.

    // 엔진을 먼저 바꿔야 그 엔진이 가진 음성 목록에서 고를 수 있다.
    await applyGoogleTtsEngine(_tts);
    await _tts.setLanguage('ko-KR');
    await _tts.setSpeechRate(kSpeechRate);
    await _tts.setPitch(_pitch);

    // 말이 왜 안 나오는지 알 수 있는 곳은 여기뿐이다. 브라우저는 소리를 막아도
    // 예외를 던지지 않고 조용히 넘어가는 경우가 많다.
    _tts.setStartHandler(() {
      _speaking = true;
      debugPrint('[MimicBot.tts] 말하기 시작');
      // 소리가 났다는 유일한 증거다. 기다리고 있던 speak()에게 알린다.
      if (_started?.isCompleted == false) _started!.complete();
    });
    _tts.setCompletionHandler(() {
      _speaking = false;
      debugPrint('[MimicBot.tts] 말하기 끝');
    });
    _tts.setCancelHandler(() => _speaking = false);
    _tts.setErrorHandler((dynamic message) {
      _speaking = false;
      debugPrint('[MimicBot.tts] 오류: $message');
    });

    _voices = await koreanVoicesByPreference(_tts);
    _voiceIndex = 0;
    if (_voices.isNotEmpty) await _setVoice(_tts, _voices.first);
  }

  /// 이전 발화를 멈추고 [text]를 말한다.
  ///
  /// 고른 음성이 소리를 못 내면 다음 후보로 바꿔 다시 시도한다. 브라우저나 기기에
  /// 따라 목록에는 있어도 실제로는 재생되지 않는 음성이 있기 때문이다.
  Future<void> speak(String text) async {
    if (text.trim().isEmpty) return;
    try {
      await _ensure();

      // 후보를 한 바퀴 돌 때까지, 소리가 나는 음성을 찾는다.
      final attempts = _voices.isEmpty ? 1 : _voices.length;
      for (var attempt = 0; attempt < attempts; attempt++) {
        if (await _speakOnce(text)) return;

        if (attempt < attempts - 1) {
          _voiceIndex = (_voiceIndex + 1) % _voices.length;
          debugPrint('[MimicBot.tts] 소리가 나지 않아 다음 음성으로 바꿉니다.');
          await _setVoice(_tts, _voices[_voiceIndex]);
        }
      }

      debugPrint('[MimicBot.tts] 모든 음성이 소리를 내지 못했습니다. '
          '브라우저나 기기의 음성 합성이 동작하지 않는 상태입니다.');
    } catch (e, st) {
      debugPrint('[MimicBot.tts] speak 실패: $e');
      debugPrint('$st');
    }
  }

  /// 지금 음성으로 한 번 말해 본다. 소리가 시작되면 true.
  Future<bool> _speakOnce(String text) async {
    // 말하고 있지 않은데도 stop()을 부르면 안 된다. 크롬에서는 cancel() 직후의
    // speak()가 무시되어 아무 소리도 나지 않는 일이 있다.
    if (_speaking) {
      await _tts.stop();
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }

    _started = Completer<void>();
    await _tts.speak(text);

    try {
      await _started!.future.timeout(_startTimeout);
      return true;
    } on TimeoutException {
      return false;
    }
  }

  Future<void> stop() => _tts.stop();

  void dispose() {
    _tts.stop();
  }
}
