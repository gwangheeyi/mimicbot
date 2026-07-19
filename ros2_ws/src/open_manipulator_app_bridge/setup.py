from glob import glob
import os
from setuptools import find_packages, setup


PACKAGE_NAME = "open_manipulator_app_bridge"


setup(
    name=PACKAGE_NAME,
    version="0.0.1",
    packages=find_packages(
        exclude=["test"],
    ),
    data_files=[
        (
            "share/ament_index/resource_index/packages",
            [f"resource/{PACKAGE_NAME}"],
        ),
        (
            f"share/{PACKAGE_NAME}",
            ["package.xml"],
        ),
        (
            f"share/{PACKAGE_NAME}/config",
            glob("config/*.yaml"),
        ),
        (
            f"share/{PACKAGE_NAME}/docs",
            glob("docs/*.md"),
        ),
    ],
    install_requires=[
        "setuptools",
        "fastapi",
        "uvicorn",
        "pyyaml",
    ],
    zip_safe=True,
    maintainer="home",
    maintainer_email="home@example.com",
    description="Flutter 앱과 OMX-AI ROS2를 연결하는 브리지",
    license="Apache-2.0",
    entry_points={
        "console_scripts": [
            (
                'app_bridge_server = open_manipulator_app_bridge.app_bridge_server:main'
            ),
        ],
    },
)
