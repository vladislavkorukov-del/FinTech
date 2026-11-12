import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' hide Text;

import '../l10n_widgets.dart';

/// 1.55: crop a photo to a card's shape. The photo moves and zooms under a
/// fixed frame of [aspect] (width ÷ height) and always covers it; «Готово»
/// returns the framed part as PNG bytes, at most [maxWidth] pixels wide.
class PhotoCropScreen extends StatefulWidget {
  const PhotoCropScreen({
    super.key,
    required this.bytes,
    this.aspect = 2,
    this.maxWidth = 1600,
    this.title = 'Фото мечты',
  });

  final Uint8List bytes;
  final double aspect;
  final int maxWidth;
  final String title;

  /// The image region (in image pixels) shown inside a [frame] when the image
  /// is drawn at [scale] with its top-left corner at [offset] from the frame's
  /// top-left corner.
  static Rect cropRect({
    required Size frame,
    required double scale,
    required Offset offset,
  }) => Rect.fromLTWH(
    -offset.dx / scale,
    -offset.dy / scale,
    frame.width / scale,
    frame.height / scale,
  );

  /// Keeps the image covering the frame: the offset may not reveal an edge.
  static Offset clampOffset({
    required Size frame,
    required Size image,
    required double scale,
    required Offset offset,
  }) => Offset(
    offset.dx.clamp(math.min(0, frame.width - image.width * scale), 0),
    offset.dy.clamp(math.min(0, frame.height - image.height * scale), 0),
  );

  /// Draws [source] of [image] into a PNG of the requested aspect.
  static Future<Uint8List> render(
    ui.Image image,
    Rect source, {
    required double aspect,
    required int maxWidth,
  }) async {
    final width = math.max(1, math.min(maxWidth, source.width.round()));
    final height = math.max(1, (width / aspect).round());
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawImageRect(
      image,
      source,
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      Paint()..filterQuality = FilterQuality.high,
    );
    final picture = recorder.endRecording();
    final out = await picture.toImage(width, height);
    picture.dispose();
    try {
      final data = await out.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) {
        throw const FormatException('Не удалось обрезать фото.');
      }
      return data.buffer.asUint8List();
    } finally {
      out.dispose();
    }
  }

  @override
  State<PhotoCropScreen> createState() => _PhotoCropScreenState();
}

class _PhotoCropScreenState extends State<PhotoCropScreen> {
  ui.Image? _image;
  Object? _error;
  bool _saving = false;
  double _zoom = 1;
  Offset _offset = Offset.zero;
  Size _frame = Size.zero;
  bool _placed = false;

  // Gesture start.
  double _startScale = 1;
  Offset _startOffset = Offset.zero, _startFocal = Offset.zero;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  Future<void> _decode() async {
    try {
      // Large camera photos are decoded at most 3000 px wide.
      final buffer = await ui.ImmutableBuffer.fromUint8List(widget.bytes);
      final codec = await ui.instantiateImageCodecWithSize(
        buffer,
        getTargetSize: (w, h) =>
            ui.TargetImageSize(width: w > 3000 ? 3000 : null),
      );
      final frame = await codec.getNextFrame();
      codec.dispose();
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      setState(() => _image = frame.image);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  Size get _imageSize =>
      Size(_image!.width.toDouble(), _image!.height.toDouble());

  double get _cover => math.max(
    _frame.width / _imageSize.width,
    _frame.height / _imageSize.height,
  );

  double get _scale => _cover * _zoom;

  void _place(Size frame) {
    if (_placed && frame == _frame) return;
    _frame = frame;
    _zoom = 1;
    // Start centered.
    _offset = Offset(
      (frame.width - _imageSize.width * _scale) / 2,
      (frame.height - _imageSize.height * _scale) / 2,
    );
    _placed = true;
  }

  Future<void> _done() async {
    final image = _image;
    if (image == null || _saving) return;
    setState(() => _saving = true);
    try {
      final rect = PhotoCropScreen.cropRect(
        frame: _frame,
        scale: _scale,
        offset: _offset,
      );
      final png = await PhotoCropScreen.render(
        image,
        rect,
        aspect: widget.aspect,
        maxWidth: widget.maxWidth,
      );
      if (mounted) Navigator.pop(context, png);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.title),
        actions: [
          TextButton(
            key: const ValueKey('photo-crop-done'),
            onPressed: image == null || _saving ? null : _done,
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            child: const Text('Готово'),
          ),
        ],
      ),
      body: _error != null
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Не удалось открыть фото. Выберите другое.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white),
                ),
              ),
            )
          : image == null
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
              builder: (context, box) {
                final width = box.maxWidth - 32;
                final frame = Size(width, width / widget.aspect);
                _place(frame);
                final top = (box.maxHeight - frame.height) / 2;
                return GestureDetector(
                  key: const ValueKey('photo-crop-area'),
                  behavior: HitTestBehavior.opaque,
                  onScaleStart: (d) {
                    _startScale = _scale;
                    _startOffset = _offset;
                    _startFocal = d.localFocalPoint - Offset(16, top);
                  },
                  onScaleUpdate: (d) => setState(() {
                    _zoom = (_startScale * d.scale / _cover).clamp(1.0, 5.0);
                    final focal = d.localFocalPoint - Offset(16, top);
                    _offset = PhotoCropScreen.clampOffset(
                      frame: _frame,
                      image: _imageSize,
                      scale: _scale,
                      offset:
                          focal -
                          (_startFocal - _startOffset) * (_scale / _startScale),
                    );
                  }),
                  child: Stack(
                    children: [
                      Positioned(
                        left: 16 + _offset.dx,
                        top: top + _offset.dy,
                        width: _imageSize.width * _scale,
                        height: _imageSize.height * _scale,
                        child: RawImage(image: image, fit: BoxFit.fill),
                      ),
                      Positioned.fill(
                        child: IgnorePointer(
                          child: CustomPaint(
                            painter: _FramePainter(
                              Rect.fromLTWH(16, top, frame.width, frame.height),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 24,
                        right: 24,
                        top: top + frame.height + 18,
                        child: const Text(
                          'Двигайте и увеличивайте фото двумя пальцами — так оно будет выглядеть на карточке.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

/// Dims everything outside the frame and draws its edge and thirds.
class _FramePainter extends CustomPainter {
  const _FramePainter(this.frame);
  final Rect frame;

  @override
  void paint(Canvas canvas, Size size) {
    final shape = RRect.fromRectAndRadius(frame, const Radius.circular(22));
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Offset.zero & size),
        Path()..addRRect(shape),
      ),
      Paint()..color = Colors.black.withValues(alpha: .62),
    );
    final line = Paint()
      ..color = Colors.white.withValues(alpha: .35)
      ..strokeWidth = .8;
    for (final k in [1 / 3, 2 / 3]) {
      final x = frame.left + frame.width * k;
      final y = frame.top + frame.height * k;
      canvas.drawLine(Offset(x, frame.top), Offset(x, frame.bottom), line);
      canvas.drawLine(Offset(frame.left, y), Offset(frame.right, y), line);
    }
    canvas.drawRRect(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = Colors.white.withValues(alpha: .9),
    );
  }

  @override
  bool shouldRepaint(_FramePainter old) => old.frame != frame;
}
