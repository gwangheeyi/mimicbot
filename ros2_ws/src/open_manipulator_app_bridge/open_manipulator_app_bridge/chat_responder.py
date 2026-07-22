"""ollama(qwen3:4b)로 사용자의 말에 짧게 대답합니다(자율 화면의 음성 대화).

앱이 사용자의 말을 보내면 로컬 qwen3가 한국어로 한두 문장 답을 만들고, 앱은
그 답을 TTS로 읽어 줍니다. 인터넷이나 외부 API 키 없이 로컬에서 동작합니다.
CPU 추론이라 몇 초~수십 초 걸릴 수 있어, 앱은 "생각 중…"을 보여주며 기다립니다.
"""

import json
import re
import threading
import time
import urllib.error
import urllib.request


OLLAMA_BASE = "http://localhost:11434"
OLLAMA_URL = f"{OLLAMA_BASE}/api/chat"
DEFAULT_MODEL = "qwen3:4b"
DEFAULT_TIMEOUT = 60.0
ROBOT_NAME = "미키"

# 예열(모델 로딩)이 여러 번 겹치지 않도록 하나만 진행하게 합니다.
_warm_lock = threading.Lock()

SYSTEM_PROMPT = (
    f"너는 '{ROBOT_NAME}'라는 친근한 어린이 도우미 로봇이야. "
    "사용자의 말에 한국어로 짧고 다정하게 한두 문장으로 대답해. "
    "말로 읽어 줄 대답이라 마크다운, 이모지, 괄호, 특수기호 없이 "
    "자연스러운 문장으로만 답해. 모르는 건 모른다고 솔직하게 말해. "
    '생각 과정은 절대 쓰지 말고, 반드시 아래 JSON 형식으로만 답해: '
    '{"reply": "미키의 한두 문장 대답"}'
)

# 최근 대화 몇 개만 기억해 문맥을 잇습니다(무한히 늘지 않도록 제한).
_MAX_HISTORY = 8
_history: list[dict[str, str]] = []

# qwen3가 혹시 남기는 사고 과정(<think>...</think>)을 지웁니다.
_THINK_RE = re.compile(r"<think>.*?</think>", re.DOTALL)

# 이모지·그림문자. TTS로 읽으면 지저분하므로 제거합니다(모델이 지시를 어기고
# 이모지를 넣는 경우가 있습니다).
_EMOJI_RE = re.compile(
    "["
    "\U0001f300-\U0001faff"  # 각종 그림문자·이모지
    "\U00002600-\U000027bf"  # 기타 기호·딩뱃
    "\U0001f1e6-\U0001f1ff"  # 국기
    "\U00002190-\U000021ff"  # 화살표
    "\U00002b00-\U00002bff"  # 기타 기호·화살표
    "\U0000fe0f"             # variation selector
    "]",
    flags=re.UNICODE,
)


def _clean(text: str) -> str:
    text = _THINK_RE.sub("", text)
    text = _EMOJI_RE.sub("", text)
    # 이모지를 지운 자리에 생긴 겹공백을 정리합니다.
    return re.sub(r"[ \t]{2,}", " ", text).strip()


# 모델이 낸 JSON({"reply": "..."})에서 대답 문장만 뽑습니다.
# 형식이 어긋나면(그냥 문장을 냈다면) 사고 과정만 지우고 그대로 씁니다.
def _extract_reply(content: str) -> str:
    cleaned = _clean(content)
    if not cleaned:
        return ""

    try:
        parsed = json.loads(cleaned)
    except (json.JSONDecodeError, TypeError):
        return cleaned

    if isinstance(parsed, dict):
        reply = parsed.get("reply") or parsed.get("response") or ""
        return str(reply).strip()

    return cleaned


# 대화 기록을 처음부터 다시 시작합니다.
def reset_history() -> None:
    _history.clear()


# ollama 서버가 응답하는지 확인합니다.
def _server_up() -> bool:
    try:
        with urllib.request.urlopen(
            f"{OLLAMA_BASE}/api/tags",
            timeout=3.0,
        ) as response:
            return response.status == 200
    except (urllib.error.URLError, TimeoutError, OSError):
        return False


# qwen3:4b를 미리 메모리에 올려 둡니다(예열). 이렇게 해 두면 첫 대화의 모델
# 로딩 시간이 사라져 대답이 바로 나옵니다. keep_alive 동안 메모리에 머뭅니다.
#
# 깨우기 직후에는 ollama 서버가 아직 부팅 중일 수 있어, 서버가 뜰 때까지
# 잠깐 기다린 뒤 로딩합니다. 이 함수는 백그라운드 스레드에서 부릅니다.
def warmup(
    model: str = DEFAULT_MODEL,
    wait_server: float = 40.0,
    load_timeout: float = 180.0,
) -> bool:
    # 이미 예열 중이면 겹치지 않게 건너뜁니다.
    if not _warm_lock.acquire(blocking=False):
        return False

    try:
        waited = 0.0
        while waited < wait_server and not _server_up():
            time.sleep(2.0)
            waited += 2.0

        if not _server_up():
            return False

        # prompt 없이 model만 주면 ollama가 모델을 메모리에 올리기만 합니다.
        # 최초 로딩부터 사고 과정(--no-thinking)을 꺼 두어 이후 대답이 빠릅니다.
        payload = {"model": model, "think": False, "keep_alive": "30m"}
        data = json.dumps(payload).encode("utf-8")
        request = urllib.request.Request(
            f"{OLLAMA_BASE}/api/generate",
            data=data,
            headers={"Content-Type": "application/json"},
        )

        try:
            with urllib.request.urlopen(
                request,
                timeout=load_timeout,
            ) as response:
                response.read()
            return True
        except (urllib.error.URLError, TimeoutError, OSError):
            return False
    finally:
        _warm_lock.release()


# 사용자의 말에 대한 한두 문장짜리 대답을 돌려줍니다.
# ollama가 없거나 응답이 비면 None을 돌려주고, 그때는 앱이 대체 문구를 씁니다.
def answer(
    message: str,
    model: str = DEFAULT_MODEL,
    timeout: float = DEFAULT_TIMEOUT,
) -> str | None:
    _history.append({"role": "user", "content": message})
    del _history[:-_MAX_HISTORY]

    payload = {
        "model": model,
        "think": False,        # 사고 과정 출력을 끕니다.
        # JSON만 내도록 강제합니다. qwen3가 think:false만으로는 사고 과정을
        # 본문에 쏟아내기도 하는데, 형식을 JSON으로 묶으면 깔끔한 대답만 나옵니다.
        "format": "json",
        "stream": False,
        "keep_alive": "10m",   # 다음 대답이 빠르도록 모델을 잠시 띄워 둡니다.
        "options": {
            "temperature": 0.7,
            "num_predict": 200,  # 짧은 대답이라 길게 뽑을 필요가 없습니다.
        },
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT},
            *_history,
        ],
    }

    data = json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(
        OLLAMA_URL,
        data=data,
        headers={"Content-Type": "application/json"},
    )

    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            body = json.loads(response.read().decode("utf-8"))
    except (urllib.error.URLError, TimeoutError, OSError, json.JSONDecodeError):
        # 실패한 발화는 문맥에서 빼 다음 요청이 오염되지 않게 합니다.
        _history.pop()
        return None

    reply = _extract_reply(body.get("message", {}).get("content", ""))

    if not reply:
        _history.pop()
        return None

    _history.append({"role": "assistant", "content": reply})
    del _history[:-_MAX_HISTORY]

    return reply
