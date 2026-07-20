import 'package:flutter/material.dart';

import 'camera_stream_view.dart';

/// 영상 스트림에 세로 줌 슬라이더를 얹은 화면.
///
/// 확대·축소는 받은 영상을 화면에서 키우고 줄이는 방식(디지털 줌)이라
/// 서버나 카메라 설정을 건드리지 않고 어느 플랫폼에서든 똑같이 동작한다.
class ZoomableStreamView extends StatefulWidget {
  const ZoomableStreamView({
    super.key,
    required this.streamUrl,
    this.minZoom = 0.4,
    this.maxZoom = 4.0,
  });

  final String streamUrl;

  /// 축소 한계. 1보다 작아야 화면 밖으로 나간 부분까지 볼 수 있다.
  final double minZoom;
  final double maxZoom;

  @override
  State<ZoomableStreamView> createState() => _ZoomableStreamViewState();
}

class _ZoomableStreamViewState extends State<ZoomableStreamView> {
  double _zoom = 1.0;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // 원본 크기일 때는 변형을 걸지 않고 그대로 그린다.
        //
        // 웹에서 영상은 `<img>` 플랫폼 뷰라, Transform·ClipRect 안에 넣으면
        // 브라우저 합성 단계에서 화면에 나오지 않는 경우가 있다. 대부분은 1배로
        // 보므로, 확대·축소할 때만 감싸서 평소에는 이 문제를 아예 만나지 않게 한다.
        if (_zoom == 1.0)
          CameraStreamView(streamUrl: widget.streamUrl)
        else
          // 가운데를 기준으로 확대하고 패널 밖은 잘라낸다.
          ClipRect(
            child: Transform.scale(
              scale: _zoom,
              child: CameraStreamView(streamUrl: widget.streamUrl),
            ),
          ),
        Positioned(
          right: 4,
          top: 56,
          bottom: 44,
          child: Column(
            children: [
              const Icon(Icons.zoom_in, size: 18, color: Colors.white70),
              // 슬라이더를 270도 돌려 세운다. 위쪽이 확대, 아래쪽이 축소.
              Expanded(
                child: RotatedBox(
                  quarterTurns: 3,
                  child: Slider(
                    value: _zoom.clamp(widget.minZoom, widget.maxZoom),
                    min: widget.minZoom,
                    max: widget.maxZoom,
                    onChanged: (value) => setState(() => _zoom = value),
                  ),
                ),
              ),
              const Icon(Icons.zoom_out, size: 18, color: Colors.white70),
              const SizedBox(height: 4),
              // 배율을 누르면 원본 크기로 되돌린다.
              GestureDetector(
                onTap: () => setState(() => _zoom = 1.0),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${_zoom.toStringAsFixed(1)}배',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
