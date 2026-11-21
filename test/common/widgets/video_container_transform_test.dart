import 'package:PiliPlus/common/widgets/page_transition/video_container_transform.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

Widget _detailPage() => const Scaffold(body: Center(child: Text('detail')));

int _routeSeq = 0;

Widget _app({
  required Widget detail,
  required String detailName,
  required String otherName,
  PageTransitionsBuilder builder = const _PlainTransitionsBuilder(),
}) {
  return GetMaterialApp(
    theme: ThemeData(
      useMaterial3: true,
      pageTransitionsTheme: PageTransitionsTheme(
        builders: {TargetPlatform.android: builder},
      ),
    ),
    defaultTransition: Transition.native,
    initialRoute: '/',
    getPages: [
      GetPage(name: '/', page: () => const Scaffold(body: Text('home'))),
      GetPage(name: detailName, page: () => detail),
      GetPage(
        name: otherName,
        page: () => const Scaffold(body: Center(child: Text('other'))),
      ),
    ],
  );
}

Future<void> _openDetail(
  WidgetTester tester, {
  Map<String, Object?>? arguments,
  PageTransitionsBuilder builder = const _PlainTransitionsBuilder(),
  bool wrapPage = false,
}) async {
  tester.view.physicalSize = _screen;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  _routeSeq++;
  final String detailName = '/detail$_routeSeq';
  final String otherName = '/other$_routeSeq';
  await tester.pumpWidget(
    _app(
      builder: builder,
      detailName: detailName,
      otherName: otherName,
      detail: wrapPage
          ? VideoCardEntryTransform(child: _detailPage())
          : _detailPage(),
    ),
  );
  await tester.pumpAndSettle();
  Get.toNamed(detailName, arguments: arguments);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 8));
}

PredictiveBackEvent _backEvent(double progress) {
  return PredictiveBackEvent.fromMap(<String?, Object?>{
    'touchOffset': const <Object?>[0.0, 400.0],
    'progress': progress,
    'swipeEdge': 1,
  });
}

Size _detailSize(WidgetTester tester) {
  return tester.getSize(find.byType(Scaffold).last);
}

/// 取页面外层形变矩阵的横向缩放，1 表示已经完全展开。
double _pageScale(WidgetTester tester) {
  final Finder finder = find.byKey(videoCardTransformKey);
  if (finder.evaluate().isEmpty) return 1.0;
  return tester.widget<Transform>(finder).transform.storage[0];
}

VideoCardEntryTransformState _state(WidgetTester tester) {
  return tester.state<VideoCardEntryTransformState>(
    find.byType(VideoCardEntryTransform).last,
  );
}

void main() {
  group('videoTransitionRect', () {
    test('starts at the origin and ends at full screen', () {
      expect(videoTransitionRect(_origin, _screen, 0), _origin);
      expect(videoTransitionRect(_origin, _screen, 1), Offset.zero & _screen);
    });

    test('moves the left edge towards the screen edge', () {
      final double mid = videoTransitionRect(_origin, _screen, 0.5).left;
      expect(mid, lessThan(_origin.left));
      expect(mid, greaterThan(0));
    });
  });

  group('videoTransitionMatrix', () {
    test('is identity at the end', () {
      expect(videoTransitionMatrix(_origin, _screen, 1), Matrix4.identity());
    });

    test('scales the page uniformly out of the card rect', () {
      final Matrix4 matrix = videoTransitionMatrix(_origin, _screen, 0);
      final Offset topLeft = MatrixUtils.transformPoint(matrix, Offset.zero);
      final Offset topRight =
          MatrixUtils.transformPoint(matrix, Offset(_screen.width, 0));
      expect(topLeft, _origin.topLeft);
      expect(topRight, _origin.topLeft + const Offset(200, 0));
      expect(matrix.storage[0], closeTo(200 / 400, 1e-9));
      expect(matrix.storage[5], closeTo(200 / 400, 1e-9));
    });
  });

  group('videoTransitionPageOpacity', () {
    test('fades in at the very beginning only', () {
      expect(videoTransitionPageOpacity(0), 0);
      expect(videoTransitionPageOpacity(0.15), 1);
      expect(videoTransitionPageOpacity(0.8), 1);
    });
  });

  group('videoOriginRectOf', () {
    test('reads rect from arguments', () {
      expect(
        videoOriginRectOf(<String, Object?>{'originRect': _origin}),
        _origin,
      );
    });

    test('returns null for missing or wrong types', () {
      expect(videoOriginRectOf(null), isNull);
      expect(videoOriginRectOf(<String, Object?>{}), isNull);
      expect(videoOriginRectOf(<String, Object?>{'originRect': 'x'}), isNull);
      expect(videoOriginRectOf(<Object?>[]), isNull);
    });
  });

  group('VideoCardPageTransitionsBuilder', () {
    testWidgets('wraps routes that carry an origin rect', (tester) async {
      await _openDetail(
        tester,
        arguments: <String, Object?>{'originRect': _origin},
        builder: const VideoCardPageTransitionsBuilder(),
      );
      expect(find.byType(VideoCardEntryTransform), findsOneWidget);
      await tester.pumpAndSettle();
      expect(_pageScale(tester), closeTo(1.0, 1e-9));
    });

    testWidgets('leaves routes without an origin rect alone', (tester) async {
      await _openDetail(
        tester,
        builder: const VideoCardPageTransitionsBuilder(),
      );
      expect(find.byType(VideoCardEntryTransform), findsNothing);
      await tester.pumpAndSettle();
      expect(_detailSize(tester).width, _screen.width);
    });
  });

  group('VideoCardEntryTransform', () {
    testWidgets('grows the page content out of the card rect', (tester) async {
      await _openDetail(
        tester,
        arguments: <String, Object?>{'originRect': _origin},
        wrapPage: true,
      );
      final double early = _pageScale(tester);
      await tester.pumpAndSettle();
      final double settled = _pageScale(tester);
      expect(early, lessThan(settled));
      expect(settled, closeTo(1.0, 1e-9));
      expect(early, lessThan(0.6));
    });

    testWidgets('keeps the page untouched without an origin rect',
        (tester) async {
      await _openDetail(tester, wrapPage: true);
      final Size before = _detailSize(tester);
      expect(before.width, _screen.width);
      await tester.pumpAndSettle();
      expect(_detailSize(tester).width, before.width);
    });

    testWidgets('follows the back gesture and reports it as consumed',
        (tester) async {
      await _openDetail(
        tester,
        arguments: <String, Object?>{'originRect': _origin},
        wrapPage: true,
      );
      await tester.pumpAndSettle();
      final VideoCardEntryTransformState state = _state(tester);
      expect(state.handleStartBackGesture(_backEvent(0.5)), isTrue);
      await tester.pump();
      // 卡片宽度是全屏的一半，t=0.5 时宽度插值到 0.75。
      expect(_pageScale(tester), closeTo(0.75, 1e-6));
      state.handleUpdateBackGestureProgress(_backEvent(0.2));
      await tester.pump();
      expect(_pageScale(tester), closeTo(0.9, 1e-6));
      state.handleCancelBackGesture();
      await tester.pumpAndSettle();
      expect(_pageScale(tester), closeTo(1.0, 1e-9));
    });

    testWidgets('drives the route animation so the page below stays visible',
        (tester) async {
      await _openDetail(
        tester,
        arguments: <String, Object?>{'originRect': _origin},
        wrapPage: true,
      );
      await tester.pumpAndSettle();
      final VideoCardEntryTransformState state = _state(tester);
      final ModalRoute<dynamic> route = ModalRoute.of(
        tester.element(find.byType(VideoCardEntryTransform).last),
      )!;
      expect(state.handleStartBackGesture(_backEvent(0.4)), isTrue);
      await tester.pump();
      // 路由动画跟着手指后退，下层页面才会被绘制（黑屏问题的根因）。
      expect(route.animation!.value, closeTo(0.6, 1e-6));
      // 拖到底也保留一点页面，不会缩成一个点。
      state.handleUpdateBackGestureProgress(_backEvent(1.0));
      await tester.pump();
      expect(route.animation!.value, 0);
      expect(_pageScale(tester), greaterThan(200 / 400));
      state.handleCancelBackGesture();
      await tester.pumpAndSettle();
      expect(route.animation!.value, 1);
    });

    testWidgets('collapses back to the card before popping', (tester) async {
      await _openDetail(
        tester,
        arguments: <String, Object?>{'originRect': _origin},
        wrapPage: true,
      );
      await tester.pumpAndSettle();
      final VideoCardEntryTransformState state = _state(tester);
      expect(state.handleStartBackGesture(_backEvent(0.3)), isTrue);
      await tester.pump();
      state.handleCommitBackGesture();
      await tester.pump(const Duration(milliseconds: 20));
      expect(find.text('detail'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('detail'), findsNothing);
      expect(find.text('home'), findsOneWidget);
    });

    testWidgets('ignores gestures when the route is not current',
        (tester) async {
      await _openDetail(
        tester,
        arguments: <String, Object?>{'originRect': _origin},
        wrapPage: true,
      );
      await tester.pumpAndSettle();
      final VideoCardEntryTransformState state = _state(tester);
      Get.toNamed('/other$_routeSeq');
      await tester.pumpAndSettle();
      expect(state.handleStartBackGesture(_backEvent(0.5)), isFalse);
    });

    testWidgets('ignores gestures without an origin rect', (tester) async {
      await _openDetail(tester, wrapPage: true);
      await tester.pumpAndSettle();
      expect(_state(tester).handleStartBackGesture(_backEvent(0.5)), isFalse);
    });
  });
}
