import 'package:PiliPlus/common/widgets/page_transition/video_container_transform.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

const _screen = Size(400, 800);
const _origin = Rect.fromLTWH(20, 40, 200, 100);

/// 只做几何隔离用：不添加任何自身转场。
class _PlainTransitionsBuilder extends PageTransitionsBuilder {
  const _PlainTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return child;
  }
}

Widget _app({Map<String, Object?>? arguments}) {
  return GetMaterialApp(
    theme: ThemeData(
      useMaterial3: true,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {TargetPlatform.android: _PlainTransitionsBuilder()},
      ),
    ),
    defaultTransition: Transition.native,
    initialRoute: '/',
    getPages: [
      GetPage(name: '/', page: () => const Scaffold(body: Text('home'))),
      GetPage(
        name: '/detail',
        page: () => const VideoCardEntryTransform(
          child: Scaffold(body: Center(child: Text('detail'))),
        ),
      ),
    ],
  );
}

void main() {
  group('videoTransitionRect', () {
    test('starts on the card and ends on the full screen', () {
      expect(videoTransitionRect(_origin, _screen, 0), _origin);
      expect(videoTransitionRect(_origin, _screen, 1), Offset.zero & _screen);
    });

    test('moves monotonically between the two', () {
      final quarter = videoTransitionRect(_origin, _screen, 0.25);
      final half = videoTransitionRect(_origin, _screen, 0.5);
      expect(quarter.left, lessThan(_origin.left));
      expect(half.left, lessThan(quarter.left));
      expect(half.width, greaterThan(quarter.width));
      expect(half.width, lessThan(_screen.width));
    });

    test('clamps out of range progress', () {
      expect(videoTransitionRect(_origin, _screen, -1), _origin);
      expect(videoTransitionRect(_origin, _screen, 2), Offset.zero & _screen);
    });
  });

  group('videoTransitionMatrix', () {
    test('identity at the end', () {
      expect(videoTransitionMatrix(Offset.zero & _screen, _screen, 1),
          Matrix4.identity());
    });

    test('scales the page uniformly out of the card rect', () {
      final matrix = videoTransitionMatrix(_origin, _screen, 0);
      // 页面左上角对齐卡片左上角。
      expect(MatrixUtils.transformPoint(matrix, Offset.zero), _origin.topLeft);
      // 页面宽度缩放到卡片宽度。
      expect(
        MatrixUtils.transformPoint(matrix, Offset(_screen.width, 0)),
        _origin.topLeft + Offset(_origin.width, 0),
      );
      // 等比缩放：纵向缩放比与横向一致，所以内容不变形。
      final double scaleY = (MatrixUtils.transformPoint(
                matrix,
                Offset(0, _screen.height),
              )
              .dy -
          _origin.top) /
          _screen.height;
      expect(scaleY, closeTo(_origin.width / _screen.width, 1e-9));
    });
  });

  group('videoTransitionPageOpacity', () {
    test('fades in quickly and stays visible', () {
      expect(videoTransitionPageOpacity(0), 0);
      expect(videoTransitionPageOpacity(0.075), 0.5);
      expect(videoTransitionPageOpacity(0.15), 1);
      expect(videoTransitionPageOpacity(1), 1);
    });
  });

  group('videoOriginRectOf', () {
    test('reads the rect from the route arguments', () {
      expect(videoOriginRectOf({'originRect': _origin}), _origin);
      expect(videoOriginRectOf({'originRect': 'x'}), isNull);
      expect(videoOriginRectOf(<String, Object?>{}), isNull);
      expect(videoOriginRectOf(null), isNull);
    });
  });

  group('VideoCardEntryTransform', () {
    testWidgets('grows the page content out of the card rect', (tester) async {
      tester.view.physicalSize = _screen;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app(arguments: {'originRect': _origin}));
      Get.toNamed('/detail', arguments: {'originRect': _origin});
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));

      final early = tester.getRect(find.text('detail'));
      await tester.pumpAndSettle();
      final settled = tester.getRect(find.text('detail'));

      expect(early.width, lessThan(settled.width));
      expect(early.center.dx, isNot(settled.center.dx));
      expect(settled.center, const Offset(200, 400));
    });

    testWidgets('keeps the page untouched without an origin rect', (
      tester,
    ) async {
      tester.view.physicalSize = _screen;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app());
      Get.toNamed('/detail');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      final early = tester.getRect(find.text('detail'));
      await tester.pumpAndSettle();
      final settled = tester.getRect(find.text('detail'));
      expect(early, settled);
    });
  });
}
