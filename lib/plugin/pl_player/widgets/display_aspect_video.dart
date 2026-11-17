import 'dart:async';

import 'package:PiliPlus/plugin/pl_player/models/video_fit_type.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// Sizes [SimpleVideo] by the media's real display aspect ratio instead of the
/// surface [VideoController.rect].
///
/// The SurfaceTexture size callback can be dropped (stale epoch/generation),
/// which leaves [VideoController.rect] at the previous video's resolution.
/// [SimpleVideo] then renders the frame into that stale box and a portrait
/// video ends up squeezed into a landscape one. Forcing the box aspect from
/// [Player.stream.size] (already rotation-corrected, equal to the buffer size)
/// keeps the pixels untouched and only fixes the box.
class DisplayAspectVideo extends StatefulWidget {
  const DisplayAspectVideo({
    required this.controller,
    required this.fit,
    this.fill = const Color(0xFF000000),
    super.key,
  });

  final VideoController controller;
  final VideoFitType fit;
  final Color fill;

  @override
  State<DisplayAspectVideo> createState() => _DisplayAspectVideoState();
}

class _DisplayAspectVideoState extends State<DisplayAspectVideo> {
  StreamSubscription<(int, int)>? _sizeSubscription;
  int _sourceWidth = 0;
  int _sourceHeight = 0;
  bool _reportedStaleRect = false;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(covariant DisplayAspectVideo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      _sizeSubscription?.cancel();
      _listen();
    }
  }

  @override
  void dispose() {
    _sizeSubscription?.cancel();
    super.dispose();
  }

  void _listen() {
    final player = widget.controller.player;
    _sourceWidth = player.state.width;
    _sourceHeight = player.state.height;
    _reportedStaleRect = false;
    _sizeSubscription = player.stream.size.listen(_onSize);
  }

  void _onSize((int, int) size) {
    if (size.$1 == _sourceWidth && size.$2 == _sourceHeight) return;
    _sourceWidth = size.$1;
    _sourceHeight = size.$2;
    _reportedStaleRect = false;
    if (!mounted) return;
    setState(() {});
    _reportStaleRect();
  }

  void _reportStaleRect() {
    if (!kDebugMode || _reportedStaleRect) return;
    final rect = widget.controller.rect.value;
    if (rect == null) return;
    if ((rect.width - _sourceWidth).abs() < 1 &&
        (rect.height - _sourceHeight).abs() < 1) {
      return;
    }
    _reportedStaleRect = true;
    debugPrint(
      '[DisplayAspectVideo] surface rect ${rect.width}x${rect.height} '
      '!= display size ${_sourceWidth}x$_sourceHeight, '
      'box aspect forced to '
      '${resolveVideoBoxAspect(widget.fit, _sourceWidth, _sourceHeight)}',
    );
  }

  @override
  Widget build(BuildContext context) {
    return SimpleVideo(
      controller: widget.controller,
      fill: widget.fill,
      aspectRatio: resolveVideoBoxAspect(
        widget.fit,
        _sourceWidth,
        _sourceHeight,
      ),
    );
  }
}
