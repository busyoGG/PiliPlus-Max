import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:PiliPlus/common/widgets/progress_bar/audio_video_progress_bar.dart';

void main() {
  testWidgets('drag fires onDragStart/onDragUpdate/onSeek', (tester) async {
    var starts = 0;
    var updates = 0;
    var seeks = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              child: ProgressBar(
                progress: 200,
                buffered: 200,
                total: 300,
                baseBarColor: const Color(0x33FFFFFF),
                progressBarColor: Colors.blue,
                bufferedBarColor: Colors.blueGrey,
                thumbColor: Colors.blue,
                thumbGlowColor: Colors.blue,
                barHeight: 4,
                thumbRadius: 6,
                verticalTouchPadding: 18,
                onDragStart: (details) {
                  starts++;
                },
                onDragUpdate: (details) {
                  updates++;
                },
                onSeek: (milliseconds) {
                  seeks.add(milliseconds);
                },
              ),
            ),
          ),
        ),
      ),
    );
    final center = tester.getCenter(find.byType(ProgressBar));
    final gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(-40, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(-40, 0));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    // ignore: avoid_print
    print('starts=starts  updates=updates  seeks=seeks');
    expect(starts, greaterThan(0));
    expect(updates, greaterThan(0));
    expect(seeks, isNotEmpty);
  });
}
