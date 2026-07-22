"""웹캠 손동작 → lerobot omx_follower 목표 자세.

Gazebo의 손 모방(hand_mimic_node)에서 손 인식·계산 로직(hand_metrics)을 그대로
가져와, 그 결과를 ROS2 관절이 아니라 lerobot 팔로워의 정규화 액션(-100~100)으로
매핑합니다. 웹캠+mediapipe는 백그라운드 스레드에서 돌고, 제어 루프는 get_target()
으로 최신 목표만 읽어 팔로워에 보냅니다(모터 I/O는 제어 루프에서만).

매핑:
  손목 x(0~1)  -> shoulder_pan (좌우 회전)
  손 올림 y    -> shoulder_lift / elbow_flex 를 base_pose~up_pose 사이로 (팔 올림)
  손 쥠(핀치)  -> gripper (0~100)
  wrist_flex/roll 은 base_pose 값 유지
"""

import threading
import time

import cv2
import mediapipe as mp
from mediapipe.tasks.python import BaseOptions
from mediapipe.tasks.python import vision

from hand_metrics import _interpolate, pinch_openness, raise_amount, smooth, wrist_position
from hand_mimic_config import (
    CAMERA_HEIGHT,
    CAMERA_WIDTH,
    MIN_DETECTION_CONFIDENCE,
    MIN_PRESENCE_CONFIDENCE,
    MIN_TRACKING_CONFIDENCE,
    PROCESS_RATE_HZ,
    SMOOTHING_FACTOR,
)

# 팔로워 액션 키 순서(스무딩 벡터 순서와 일치).
MOTOR_KEYS = [
    "shoulder_pan.pos",
    "shoulder_lift.pos",
    "elbow_flex.pos",
    "wrist_flex.pos",
    "wrist_roll.pos",
    "gripper.pos",
]

# mediapipe 손 뼈대 연결(랜드마커 21점). 영상에 손을 그릴 때 쓴다.
HAND_CONNECTIONS = [
    (0, 1), (1, 2), (2, 3), (3, 4),        # 엄지
    (0, 5), (5, 6), (6, 7), (7, 8),        # 검지
    (5, 9), (9, 10), (10, 11), (11, 12),   # 중지
    (9, 13), (13, 14), (14, 15), (15, 16), # 약지
    (13, 17), (17, 18), (18, 19), (19, 20),  # 소지
    (0, 17),                                # 손바닥
]


class HandMimic:
    def __init__(
        self,
        model_path: str,
        base_pose: dict[str, float],
        up_pose: dict[str, float],
        camera_index: int = 0,
        pan_left: float = 40.0,   # x=0(화면 왼쪽)일 때 shoulder_pan
        pan_right: float = -40.0,  # x=1(화면 오른쪽)일 때 shoulder_pan
        grip_closed: float = 0.0,
        grip_open: float = 100.0,
        smoothing: float = SMOOTHING_FACTOR,
    ) -> None:
        self._model_path = model_path
        self._base = base_pose
        self._up = up_pose
        self._camera_index = camera_index
        self._pan_left = pan_left
        self._pan_right = pan_right
        self._grip_closed = grip_closed
        self._grip_open = grip_open
        self._smoothing = smoothing

        self._lock = threading.Lock()
        self._target: dict[str, float] | None = None
        self._smoothed: list[float] | None = None
        # 손을 그려 넣은 최신 프레임(JPEG). /hand_stream 이 이걸 흘려보낸다.
        self._jpeg: bytes | None = None
        self._running = False
        self._thread: threading.Thread | None = None
        self._error: str | None = None
        self._frame_ts_ms = 0

    # 백그라운드 스레드 시작(웹캠 열고 인식 루프).
    def start(self) -> None:
        if self._running:
            return
        self._running = True
        self._smoothed = None
        self._target = None
        self._thread = threading.Thread(target=self._loop, daemon=True)
        self._thread.start()

    def stop(self) -> None:
        self._running = False
        if self._thread is not None:
            self._thread.join(timeout=2.0)
            self._thread = None

    # 제어 루프가 읽는 최신 목표(정규화 액션). 아직 손이 안 잡혔으면 None.
    def get_target(self) -> dict[str, float] | None:
        with self._lock:
            return dict(self._target) if self._target else None

    # MJPEG 스트림이 읽는 최신 프레임(손 그려짐). 아직 없으면 None.
    def get_jpeg(self) -> bytes | None:
        with self._lock:
            return self._jpeg

    def error(self) -> str | None:
        return self._error

    # 프레임에 손 랜드마크(점·뼈대)를 그린다. landmarks는 0~1 정규화 (x, y).
    def _draw(self, frame, landmarks: list[tuple[float, float]]) -> None:
        h, w = frame.shape[:2]
        pts = [(int(x * w), int(y * h)) for x, y in landmarks]
        for a, b in HAND_CONNECTIONS:
            if a < len(pts) and b < len(pts):
                cv2.line(frame, pts[a], pts[b], (0, 255, 0), 2)
        for p in pts:
            cv2.circle(frame, p, 4, (0, 0, 255), -1)

    def _make_landmarker(self) -> vision.HandLandmarker:
        options = vision.HandLandmarkerOptions(
            base_options=BaseOptions(model_asset_path=self._model_path),
            running_mode=vision.RunningMode.VIDEO,
            num_hands=1,
            min_hand_detection_confidence=MIN_DETECTION_CONFIDENCE,
            min_hand_presence_confidence=MIN_PRESENCE_CONFIDENCE,
            min_tracking_confidence=MIN_TRACKING_CONFIDENCE,
        )
        return vision.HandLandmarker.create_from_options(options)

    # 손목 x,y 와 핀치 정도를 팔로워 정규화 액션으로 매핑.
    def _hand_to_action(self, x: float, y: float, openness: float) -> list[float]:
        lift = raise_amount(y)
        return [
            _interpolate(self._pan_left, self._pan_right, x),
            _interpolate(self._base["shoulder_lift.pos"], self._up["shoulder_lift.pos"], lift),
            _interpolate(self._base["elbow_flex.pos"], self._up["elbow_flex.pos"], lift),
            _interpolate(self._base["wrist_flex.pos"], self._up.get("wrist_flex.pos", self._base["wrist_flex.pos"]), lift),
            self._base["wrist_roll.pos"],
            _interpolate(self._grip_closed, self._grip_open, openness),
        ]

    def _loop(self) -> None:
        camera = cv2.VideoCapture(self._camera_index)
        camera.set(cv2.CAP_PROP_FRAME_WIDTH, CAMERA_WIDTH)
        camera.set(cv2.CAP_PROP_FRAME_HEIGHT, CAMERA_HEIGHT)
        if not camera.isOpened():
            self._error = f"웹캠({self._camera_index})을 열 수 없습니다."
            self._running = False
            return

        try:
            landmarker = self._make_landmarker()
        except Exception as err:  # noqa: BLE001
            self._error = f"손 인식 모델 로드 실패: {err}"
            camera.release()
            self._running = False
            return

        period = 1.0 / PROCESS_RATE_HZ
        while self._running:
            loop_start = time.perf_counter()
            read_ok, frame = camera.read()
            if not read_ok:
                time.sleep(period)
                continue

            frame = cv2.flip(frame, 1)  # 거울처럼(직관적 좌우)
            rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
            self._frame_ts_ms += int(1000.0 / PROCESS_RATE_HZ)

            try:
                result = landmarker.detect_for_video(mp_image, self._frame_ts_ms)
            except Exception:  # noqa: BLE001
                result = None

            if result and result.hand_landmarks:
                landmarks = [(lm.x, lm.y) for lm in result.hand_landmarks[0]]
                x, y = wrist_position(landmarks)
                openness = pinch_openness(landmarks)
                raw = self._hand_to_action(x, y, openness)
                self._smoothed = smooth(self._smoothed, raw, self._smoothing)
                with self._lock:
                    self._target = dict(zip(MOTOR_KEYS, self._smoothed))
                self._draw(frame, landmarks)

            # 손이 있든 없든 매 프레임 인코딩해 스트림에 최신 영상을 준다.
            ok, buf = cv2.imencode(".jpg", frame)
            if ok:
                with self._lock:
                    self._jpeg = buf.tobytes()

            dt = time.perf_counter() - loop_start
            if dt < period:
                time.sleep(period - dt)

        camera.release()
