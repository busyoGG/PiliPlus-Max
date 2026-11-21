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

/// 过渡层（卡片封面）当前占据的矩形。
Rect? _coverRect(WidgetTester tester) {
  final Finder finder = find.byKey(videoCardCoverKey);
  if (finder.evaluate().isEmpty) return null;
  return tester.getRect(finder);
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

    test('maps the page exactly onto the card rect', () {
      final Matrix4 matrix = videoTransitionMatrix(_origin, _screen, 0);
      // 页面的两个角正好落到卡片矩形的两个角上。
      expect(
        MatrixUtils.transformPoint(matrix, Offset.zero),
        _origin.topLeft,
      );
      expect(
        MatrixUtils.transformPoint(matrix, Offset(_screen.width, 0)),
        _origin.topLeft + const Offset(200, 0),
      );
      expect(
        MatrixUtils.transformPoint(matrix, Offset(0, _screen.height)),
        _origin.topLeft + const Offset(0, 100),
      );
      expect(matrix.storage[0], closeTo(200 / 400, 1e-9));
      expect(matrix.storage[5], closeTo(100 / 800, 1e-9));
    });
  });

  group('videoTransitionPageOpacity', () {
    test('fades the page in only at the end', () {
      expect(videoTransitionPageOpacity(0), 0);
      expect(videoTransitionPageOpacity(0.55), 0);
      expect(videoTransitionPageOpacity(1), 1);
      expect(videoTransitionPageOpacity(0.8), inExclusiveRange(0, 1));
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
    testWidgets('grows the card content out of the card rect', (tester) async {
      await _openDetail(
        tester,
        arguments: <String, Object?>{'originRect': _origin},
        wrapPage: true,
      );
      final Rect? early = _coverRect(tester);
      expect(early, isNotNull);
      // 起点就是卡片本身的位置和大小。
      expect(early!.left, closeTo(_origin.left, 10));
      expect(early.top, closeTo(_origin.top, 10));
      expect(early.width, lessThan(_screen.width));
      // 详情页本身不再被缩放。
      expect(_pageScale(tester), 1.0);
      await tester.pumpAndSettle();
      // 长满全屏后过渡层消失。
      expect(_coverRect(tester), isNull);
      expect(_pageScale(tester), 1.0);
    });

    testWidgets('keeps the page untouched without an origin rect',
        (tester) async {
      await _openDetail(tester, wrapPage: true);
      final Size before = _detailSize(tester);
      expect(before.width, _screen.width);
      await tester.pumpAndSettle();
      expect(_detailSize(tester).width, before.width);
    });

    testWidgets('previews the back gesture without morphing to the card',
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
      // 路由动画跟着手指后退，下层页面参与绘制。
      expect(route.animation!.value, closeTo(0.6, 1e-6));
      // 按住期间只做预测性预览的轻微缩放，不缩到卡片。
      expect(
        _pageScale(tester),
        closeTo(videoCardPreviewMinScale + (1 - videoCardPreviewMinScale) * 0.6, 1e-6),
      );
      state.handleUpdateBackGestureProgress(_backEvent(0.95));
      await tester.pump();
      expect(route.animation!.value, closeTo(0.05, 1e-6));
      expect(
        _pageScale(tester),
        closeTo(videoCardPreviewMinScale + (1 - videoCardPreviewMinScale) * 0.05, 1e-6),
      );
      state.handleCancelBackGesture();
      await tester.pumpAndSettle();
      expect(_pageScale(tester), 1.0);
      expect(route.animation!.value, 1);
      expect(find.text('detail'), findsOneWidget);
    });

    testWidgets('collapses back to the card before popping', (tester) async {
      await _openDetail(
        tester,
        arguments: <String, Object?>{'originRect': _origin},
        wrapPage: true,
      );
      await tester.pumpAndSettle();
      final VideoCardEntryTransformState state = _state(tester);
      expect(state.handleStartBackGesture(_backEvent(0.7)), isTrue);
      await tester.pump();
      // 手势期间 navigator 认为用户手势在进行中。
      expect(Get.key.currentState!.userGestureInProgress, isTrue);
      state.handleCommitBackGesture();
      // 第一帧让 ticker 起步，再推进时间。
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(_coverRect(tester)?.width ?? 0, lessThan(_screen.width));
      expect(find.text('detail'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('detail'), findsNothing);
      expect(find.text('home'), findsOneWidget);
      // 返回之后不能再卡住：手势计数必须已经归还。
      expect(Get.key.currentState!.userGestureInProgress, isFalse);
    });

    testWidgets('ignores the commit event when no gesture started',
        (tester) async {
      await _openDetail(
        tester,
        arguments: <String, Object?>{'originRect': _origin},
        wrapPage: true,
      );
      await tester.pumpAndSettle();
      _state(tester).handleCommitBackGesture();
      await tester.pumpAndSettle();
      expect(find.text('detail'), findsOneWidget);
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
