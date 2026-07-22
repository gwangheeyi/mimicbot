ARM_COMMAND_TOPIC = "/arm_controller/joint_trajectory"

ARM_JOINT_NAMES = [
    "joint1",
    "joint2",
    "joint3",
    "joint4",
]

MOTION_DURATION_SECONDS = 2

MOTION_POSITIONS = {
    "home": [0.0, 0.0, 0.0, 0.0],
    "ready": [0.0, -0.7, 0.5, 0.2],
    "left": [0.8, -0.5, 0.4, 0.1],
    "right": [-0.8, -0.5, 0.4, 0.1],
    "up": [0.0, -1.0, 0.3, 0.7],
    # 차렷: 팔을 일직선으로 곧게 세운 자세.
    "attention": [0.0, 0.0, 0.0, -1.5708],
    # 경례: 차렷 자세에서 맨 끝 관절(joint4)을 90도(약 1.5708rad) 내린 자세.
    "salute": [0.0, 0.0, 0.0, 0.0],
}
