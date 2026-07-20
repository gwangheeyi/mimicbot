"""손 모방 기능의 설정값입니다.

카메라, 인식 기준, 팔·그리퍼 매핑을 한곳에 모아 두어
동작이 어색할 때 이 파일의 숫자만 고치면 되도록 했습니다.
"""

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

# joint2는 상하입니다. 화면 위(y = 0)가 팔을 든 자세입니다.
JOINT2_AT_TOP = -1.0  # y = 0
JOINT2_AT_BOTTOM = 0.3  # y = 1

# joint3·joint4는 고정합니다. 손목 하나로 네 관절을 모두 흉내 내면
# 자세가 예측하기 어려워지므로, 팔꿈치는 보기 좋은 각도로 두고 두 축만 따라 합니다.
JOINT3_FIXED = 0.5
JOINT4_FIXED = 0.2

# 손 떨림이 그대로 로봇에 전달되지 않도록 이전 값과 섞습니다.
# 0에 가까울수록 부드럽지만 반응이 늦습니다.
SMOOTHING_FACTOR = 0.35

# 팔 명령을 보내는 간격과, 로봇이 그 자세까지 가는 데 주는 시간입니다.
# 도달 시간이 전송 간격보다 조금 길어야 동작이 끊기지 않고 이어집니다.
COMMAND_PERIOD_SECONDS = 0.1
COMMAND_DURATION_SECONDS = 0.25
