"""손 모방 기능의 설정값입니다.

카메라, 인식 기준, 팔·그리퍼 매핑을 한곳에 모아 두어
동작이 어색할 때 이 파일의 숫자만 고치면 되도록 했습니다.
"""

from math import radians

# --- 카메라 -------------------------------------------------------------

# 웹캠 장치 번호. /dev/video0 이 0번입니다. 노드 파라미터로 바꿀 수 있습니다.
CAMERA_INDEX = 0
CAMERA_WIDTH = 640
CAMERA_HEIGHT = 480

# 초당 프레임 처리 횟수. 높이면 부드럽지만 CPU를 더 씁니다.
PROCESS_RATE_HZ = 20.0


# --- 토픽 ---------------------------------------------------------------

# 손 관절을 그려 넣은 영상. web_video_server가 이 토픽을 앱에 중계합니다.
ANNOTATED_IMAGE_TOPIC = "/hand_camera/image"

# 모방 시작/정지. 앱의 "모방 시작" 버튼이 브리지를 거쳐 이 토픽으로 들어옵니다.
MIMIC_ENABLE_TOPIC = "/open_manipulator/mimic_enable"

# 카메라 확보/반환. 실시간 모방 화면에 들어오면 켜서 웹캠을 열고, 나가면 꺼서
# 웹캠 장치를 반환합니다. 화면을 안 볼 때는 카메라를 잡지 않아 다른 프로그램이
# 쓸 수 있습니다.
CAMERA_ENABLE_TOPIC = "/open_manipulator/camera_enable"

# 사용할 웹캠 장치 번호(/dev/videoN의 N). 앱의 카메라 선택이 브리지를 거쳐 이
# 토픽으로 들어오면, 노드가 그 번호로 웹캠을 다시 엽니다. 컴퓨터에 카메라가
# 여러 대 붙어 있을 때(내장캠·USB웹캠 등) 어느 것으로 모방할지 고르는 데 씁니다.
CAMERA_INDEX_TOPIC = "/open_manipulator/camera_index"


# --- 손 인식 모델 -------------------------------------------------------

# mediapipe HandLandmarker 모델 파일 이름. 패키지 share/models 에 설치됩니다.
HAND_MODEL_FILENAME = "hand_landmarker.task"

MIN_DETECTION_CONFIDENCE = 0.5
MIN_PRESENCE_CONFIDENCE = 0.5
MIN_TRACKING_CONFIDENCE = 0.5


# --- 손가락 벌림(핀치) 판정 ---------------------------------------------

# 엄지 끝과 검지 끝 사이의 거리를 손바닥 크기로 나눈 비율입니다.
# 손가락을 붙이면 작아지고 벌리면 커집니다. 그리퍼가 물건을 집는 동작과
# 모양이 같아 무엇을 시키는지 눈으로 바로 알 수 있습니다.
#
# 손바닥 크기로 나누기 때문에 손이 카메라에서 멀어져 좌표가 함께 작아져도
# 비율은 그대로입니다. 거리와 무관하게 같은 기준으로 판정할 수 있습니다.
PINCH_CLOSED_RATIO = 0.25
PINCH_OPEN_RATIO = 1.50

# 그리퍼 목표가 이만큼(0~1 기준) 바뀌었을 때만 새 명령을 보냅니다.
# 매 프레임 보내면 액션 서버에 목표가 쌓여 반응이 밀립니다.
GRIPPER_CHANGE_THRESHOLD = 0.08


# --- 그리퍼 -------------------------------------------------------------

GRIPPER_ACTION_NAME = "/gripper_controller/gripper_cmd"

# URDF의 gripper_left_joint 한계는 lower=-0.011, upper=0.02 입니다.
# 한계에 딱 붙이면 컨트롤러가 목표에 도달하지 못해 계속 힘을 주므로 안쪽으로 잡습니다.
GRIPPER_OPEN_POSITION = 0.019
GRIPPER_CLOSED_POSITION = -0.010
GRIPPER_MAX_EFFORT = 10.0


# --- 팔 매핑 ------------------------------------------------------------

# 손목의 화면 위치(0~1)를 관절 각도(라디안)로 옮깁니다.
#
# joint1은 좌우 회전입니다. MOTION_POSITIONS에서 left가 +0.8, right가 -0.8이므로
# 양수가 로봇 기준 왼쪽입니다. 영상은 거울처럼 좌우를 뒤집어 보여주기 때문에
# 화면 오른쪽(x가 1에 가까움)이 사용자의 오른손 방향이고, 로봇도 오른쪽으로 갑니다.
JOINT1_AT_LEFT = 1.2  # x = 0
JOINT1_AT_RIGHT = -1.2  # x = 1

# 모방을 시작할 때 팔의 좌우 초기 방향(joint1, 라디안). 양수가 로봇 기준 왼쪽입니다.
# 대개 오른손잡이라 손이 화면 오른쪽에 잡히므로, 시작 자세를 왼쪽으로 45도 틀어
# 두어 첫 프레임에서 팔이 손 쪽(오른쪽)으로 크게 튀지 않고 자연스럽게 따라갑니다.
MIMIC_START_JOINT1 = radians(45)

# 상하(y) 매핑 — "기본은 90도로 앞을 보는 자세"를 바닥으로 두고 위로만 올립니다.
#
# 예전에는 손을 내리면 팔이 아래로 뚝 떨어졌습니다(joint2가 +0.3까지 감). 이제는
# 손을 내려도 아래의 ARM_BASE_POSE(수평으로 앞을 보는 90도 자세) 밑으로는
# 내려가지 않고, 손을 올릴수록 ARM_UP_POSE(위로 세운 자세)로 다가갑니다.
#
# 손목 화면 세로 위치 y로 '올린 정도'를 정합니다.
#   y = 0 (화면 맨 위)       -> 완전히 올린 자세 (ARM_UP_POSE)
#   y >= RAISE_NEUTRAL_Y     -> 기본 자세 (ARM_BASE_POSE), 그 아래로 내려도 유지
RAISE_NEUTRAL_Y = 0.5

# 아래 두 자세는 [joint2, joint3, joint4] 입니다. joint1(좌우)은 손 x로 따로 정하며,
# 위로 든 상태에서도 손을 좌우로 흔들면 joint1이 따라 좌우로 움직입니다.
#
# ARM_BASE_POSE: 팔이 앞을 수평으로 보는 기본 90도 자세(모방 시작 자세이자 바닥).
# ARM_UP_POSE:   손을 위로 올렸을 때 팔을 세운 자세(손목을 편 듯 위로 향함).
ARM_BASE_POSE = [-0.7, 0.5, 0.2]
ARM_UP_POSE = [-1.3, 0.3, 0.7]

# 손 떨림이 그대로 로봇에 전달되지 않도록 이전 값과 섞습니다.
# 0에 가까울수록 부드럽지만 반응이 늦습니다.
SMOOTHING_FACTOR = 0.35

# 팔 명령을 보내는 간격과, 로봇이 그 자세까지 가는 데 주는 시간입니다.
# 도달 시간이 전송 간격보다 조금 길어야 동작이 끊기지 않고 이어집니다.
COMMAND_PERIOD_SECONDS = 0.1
COMMAND_DURATION_SECONDS = 0.25
