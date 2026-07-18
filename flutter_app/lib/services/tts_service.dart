import 'package:flutter_tts/flutter_tts.dart';

/// 사용 가능한 음성 목록에서 한국어 여성 음성을 골라 [tts]에 설정한다.
///
/// 음성 이름은 플랫폼마다 다르므로(Windows: Heami/SunHi, Android/Google: 다양),
/// locale이 ko 인 음성 중 gender/name으로 여성을 추정해 선택한다.
/// 실패하면 기본 음성을 그대로 둔다.
Future<void> applyKoreanFemaleVoice(FlutterTts tts) async {
  try {
    final dynamic raw = await tts.getVoices;
    if (raw is! List) return;

    final voices = raw.whereType<Map>().map((m) {
      return m.map(
          (k, v) => MapEntry(k.toString(), (v ?? '').toString()));
    }).toList();

    final korean = voices
        .where((v) => (v['locale'] ?? '').toLowerCase().startsWith('ko'))
        .toList();
    if (korean.isEmpty) return;

    bool isFemale(String name, String gender) {
      if (gender.isNotEmpty) {
        return gender.startsWith('f') || gender.contains('female');
      }
      const femaleHints = ['female', 'heami', 'sunhi', 'woman', 'yuna', 'nari'];
      const maleHints = ['male', 'injoon', 'man'];
      if (maleHints.any(name.contains)) return false;
      return femaleHints.any(name.contains);
    }

    // 점수: SunHi(요청 음성) > 기타 신경망(natural/neural) > 여성 > 비-Desktop.
    int score(Map<String, String> v) {
      final name = (v['name'] ?? '').toLowerCase();
      final gender = (v['gender'] ?? '').toLowerCase();
      var s = 0;
      if (name.contains('sunhi')) s += 16; // 사용자가 지정한 음성 최우선
      const naturalHints = ['natural', 'neural', 'online'];
      if (naturalHints.any(name.contains)) s += 8;
      if (isFemale(name, gender)) s += 4;
      if (!name.contains('desktop')) s += 2; // OneCore/모바일 음성이 더 자연스러움
      return s;
    }

    korean.sort((a, b) => score(b).compareTo(score(a)));
    final chosen = korean.first;
    await tts.setVoice({
      'name': chosen['name'] ?? '',
      'locale': chosen['locale'] ?? 'ko-KR',
    });
  } catch (_) {
    // 음성 조회/설정 실패 시 기본 음성 유지.
  }
}

/// 한국어 여성 TTS 재생용 경량 서비스.
/// 각 화면에서 인스턴스를 만들어 인사말 등을 말할 때 사용한다.
class TtsService {
  final FlutterTts _tts = FlutterTts();
  bool _ready = false;

  Future<void> _ensure() async {
    if (_ready) return;
    await _tts.setLanguage('ko-KR');
    await _tts.setSpeechRate(0.5);
    await applyKoreanFemaleVoice(_tts);
    _ready = true;
  }

  /// 이전 발화를 멈추고 [text]를 말한다.
  Future<void> speak(String text) async {
    if (text.trim().isEmpty) return;
    await _ensure();
    await _tts.stop();
    await _tts.speak(text);
  }

  Future<void> stop() => _tts.stop();

  void dispose() {
    _tts.stop();
  }
}
