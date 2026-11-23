import 'package:PiliPlus/common/widgets/progress_bar/audio_video_progress_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _build({
  required bool draggable,
  required void Function() onDragStartCalled,
  required void Function(int milliseconds) onSeekCalled,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 300,
          child: ProgressBar(
            progress: 10,
            total: 100,
            baseBarColor: const Color(0x33FFFFFF),
            progressBarColor: const Color(0xFFFFFFFF),
            bufferedBarColor: const Color(0x1AFFFFFF),
            thumbColor: const Color(0xFFFFFFFF),
            thumbGlowColor: const Color(0x33FFFFFF),
            onDragStart: draggable
                ? (details) {
                    onDragStartCalled();
                  }
                : null,
            onSeek: (milliseconds) {
              onSeekCalled(milliseconds);
            },
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('onDragStart 由 null 变为非 null 后进度条可以拖动', (tester) async {
    var dragStartCount = 0;
    var seekMilliseconds = -1;

    await tester.pumpWidget(
      _build(
        draggable: false,
        onDragStartCalled: () => dragStartCount++,
        onSeekCalled: (milliseconds) => seekMilliseconds = milliseconds,
      ),
    );
    await tester.pumpWidget(
      _build(
        draggable: true,
        onDragStartCalled: () => dragStartCount++,
        onSeekCalled: (milliseconds) => seekMilliseconds = milliseconds,
      ),
    );

    await tester.drag(find.byType(ProgressBar), const Offset(80, 0));
    await tester.pumpAndSettle();

    expect(dragStartCount, greaterThan(0));
    expect(seekMilliseconds, greaterThan(0));
  });

  testWidgets('onDragStart 一直为 null 时进度条不响应拖动', (tester) async {
    var seekMilliseconds = -1;

    await tester.pumpWidget(
      _build(
        draggable: false,
        onDragStartCalled: () {},
        onSeekCalled: (milliseconds) => seekMilliseconds = milliseconds,
      ),
    );

    await tester.drag(
      find.byType(ProgressBar),
      const Offset(80, 0),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect(seekMilliseconds, -1);
  });
}
