from pathlib import Path
from typing import Any

import yaml
from ament_index_python.packages import get_package_share_directory


PACKAGE_NAME = "open_manipulator_app_bridge"
CONFIG_FILE_NAME = "app_bridge_config.yaml"


# ROS2 패키지의 config 디렉토리에 저장된 YAML 설정 파일을 읽어
# 애플리케이션 전체에서 사용할 설정값을 딕셔너리 형태로 반환합니다.
# 토픽 이름, 서버 주소, 포트, 로봇 명령을 한 곳에서 관리하여
# 여러 Python 파일에 동일한 상수값이 중복되는 것을 방지합니다.
def load_config() -> dict[str, Any]:
    package_share_directory = Path(
        get_package_share_directory(PACKAGE_NAME)
    )

    config_path = (
        package_share_directory
        / "config"
        / CONFIG_FILE_NAME
    )

    if not config_path.exists():
        raise FileNotFoundError(
            f"설정 파일을 찾을 수 없습니다: {config_path}"
        )

    with config_path.open(
        mode="r",
        encoding="utf-8",
    ) as config_file:
        config = yaml.safe_load(config_file)

    if not isinstance(config, dict):
        raise ValueError("설정 파일 형식이 올바르지 않습니다.")

    return config