

from glob import glob

from setuptools import find_packages, setup

package_name = 'open_manipulator_app_control'

setup(
    name=package_name,
    version='0.0.0',
    packages=find_packages(exclude=['test']),
    data_files=[
        ('share/ament_index/resource_index/packages',
            ['resource/' + package_name]),
        ('share/' + package_name, ['package.xml']),
        # 손 인식 모델(hand_landmarker.task). 노드가 share에서 찾아 읽습니다.
        ('share/' + package_name + '/models', glob('models/*.task')),
    ],
    install_requires=['setuptools'],
    zip_safe=True,
    maintainer='home',
    maintainer_email='gwanghee@gmail.com',
    description='TODO: Package description',
    license='TODO: License declaration',
    extras_require={
        'test': [
            'pytest',
        ],
    },
    entry_points={
        'console_scripts': [
            'motion_server = open_manipulator_app_control.motion_server:main',
            'hand_mimic_node = '
            'open_manipulator_app_control.hand_mimic_node:main',
        ],
    },
)
