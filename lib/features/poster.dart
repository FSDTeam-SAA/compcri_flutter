import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart' hide Text;

import '../core/design.dart';
import '../core/i18n.dart';

/// An event's image shown whole: sharp in the middle over a blurred copy of
/// itself, so a tall flyer and a wide banner both fill the frame without
/// being cropped. Tapping opens it full screen.
///
/// [aspectRatio] is width / height when known (the API sends the size of
/// uploaded images); the frame follows it within sensible limits.
class PosterImage extends StatelessWidget {
  const PosterImage({
    super.key,
    required this.image,
    required this.heroTag,
    this.aspectRatio,
  });

  final ImageProvider image;
  final Object heroTag;
  final double? aspectRatio;

  void _open(BuildContext context) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => PosterViewer(image: image, heroTag: heroTag),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final ratio = (aspectRatio ?? 4 / 3).clamp(4 / 5, 16 / 9);
    Widget fallback(Widget child) => ColoredBox(
      color: palette.tint,
      child: Center(child: child),
    );
    return Semantics(
      button: true,
      image: true,
      label: tr('View poster'),
      child: GestureDetector(
        key: const ValueKey('poster-image'),
        onTap: () => _open(context),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: AspectRatio(
            aspectRatio: ratio,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                  child: Image(
                    image: image,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => ColoredBox(color: palette.tint),
                  ),
                ),
                const ColoredBox(color: Color(0x33000000)),
                Hero(
                  tag: heroTag,
                  child: Image(
                    image: image,
                    fit: BoxFit.contain,
                    loadingBuilder: (_, child, progress) => progress == null
                        ? child
                        : fallback(
                            const CircularProgressIndicator(strokeWidth: 2),
                          ),
                    errorBuilder: (_, _, _) => fallback(
                      Text(
                        'Could not load the poster',
                        style: TextStyle(fontSize: 12, color: palette.muted),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 10,
                  bottom: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.zoom_out_map, size: 14, color: Colors.white),
                        SizedBox(width: 5),
                        Text(
                          'Tap to view',
                          style: TextStyle(fontSize: 11, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Full-screen image with pinch to zoom; double-tap zooms in and back out.
class PosterViewer extends StatefulWidget {
  const PosterViewer({super.key, required this.image, required this.heroTag});

  final ImageProvider image;
  final Object heroTag;

  @override
  State<PosterViewer> createState() => _PosterViewerState();
}

class _PosterViewerState extends State<PosterViewer> {
  final zoom = TransformationController();
  TapDownDetails? _doubleTap;

  @override
  void dispose() {
    zoom.dispose();
    super.dispose();
  }

  void _toggleZoom() {
    if (zoom.value != Matrix4.identity()) {
      zoom.value = Matrix4.identity();
      return;
    }
    final at = _doubleTap?.localPosition ?? Offset.zero;
    zoom.value = Matrix4.identity()
      ..translateByDouble(-at.dx * 1.5, -at.dy * 1.5, 0, 1)
      ..scaleByDouble(2.5, 2.5, 1, 1);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      systemOverlayStyle: appOverlayStyle(AppPalette.night),
      leading: IconButton(
        tooltip: tr('Close'),
        icon: const Icon(Icons.close),
        onPressed: () => Navigator.pop(context),
      ),
    ),
    body: GestureDetector(
      onDoubleTapDown: (details) => _doubleTap = details,
      onDoubleTap: _toggleZoom,
      child: InteractiveViewer(
        transformationController: zoom,
        maxScale: 5,
        child: Center(
          child: Hero(
            tag: widget.heroTag,
            child: Image(
              image: widget.image,
              fit: BoxFit.contain,
              loadingBuilder: (_, child, progress) => progress == null
                  ? child
                  : const CircularProgressIndicator(color: Colors.white),
              errorBuilder: (_, _, _) => const Text(
                'Could not load the poster',
                style: TextStyle(color: Colors.white70),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
