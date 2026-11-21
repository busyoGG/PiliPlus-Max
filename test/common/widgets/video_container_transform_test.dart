import 'package:PiliPlus/common/widgets/page_transition/video_container_transform.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

const _screen = Size(400, 800);
const _origin = Rect.fromLTWH(20, 40, 200, 100);

ThemeData _theme(PageTransitionsBuilder builder) {
  return ThemeData(
    useMaterial3: true,
    pageTransitionsTheme: PageTransitionsTheme(
      builders: {TargetPlatform.android: builder},
    ),
  );
}

Widget _app(PageTransitionsBuilder builder) {
  return GetMaterialApp(
    theme: _theme(builder),
    defaultTransition: Transition.native,
    initialRoute: '/',
    getPages: [
      GetPage(name: '/', page: () => const Scaffold(body: Text('home'))),
      GetPage(
        name: '/detail',
        page: () => const Scaffold(body: Text('detail')),
      ),
    ],
  );
}

class _RecordingBuilder extends PageTransitionsBuilder {
  int calls = 0;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    calls++;
    return child;
  }
}

void main() {
  group('videoTransitionRect', () {
    test('starts on the card and ends on the full screen', () {
      expect(videoTransitionRect(_origin, _screen, 0), _origin);
      expect(
        videoTransitionRect(_origin, _screen, 1),
        Offset.zero & _screen,
      );
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

  group('videoTransitionOpacity', () {
    test('cover is visible first and gone at the end', () {
      expect(videoTransitionCoverOpacity(0), 1);
      expect(videoTransitionCoverOpacity(0.5), 1);
      expect(videoTransitionCoverOpacity(0.8), lessThan(0.5));
      expect(videoTransitionCoverOpacity(1), 0);
    });

    test('page fades in over the second half', () {
      expect(videoTransitionPageOpacity(0), 0);
      expect(videoTransitionPageOpacity(0.2), 0);
      expect(videoTransitionPageOpacity(1), 1);
      expect(videoTransitionPageOpacity(0.7), lessThan(1));
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

  group('VideoContainerTransformBuilder', () {
    testWidgets('grows the cover from the card into a full page', (
      tester,
    ) async {
      tester.view.physicalSize = _screen;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app(const VideoContainerTransformBuilder()));
      tester
          .state<NavigatorState>(find.byType(Navigator))
          .push(
            GetPageRoute<void>(
              page: () => const Scaffold(body: Text('detail')),
              routeName: '/detail',
              settings: const RouteSettings(
                name: '/detail',
                arguments: {'originRect': _origin, 'cover': 'http://cover'},
              ),
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));

      final early = tester.getRect(find.byType(Image));
      expect(early.left, greaterThanOrEqualTo(0));
      expect(early.width, greaterThan(_origin.width));
      expect(early.width, lessThan(_screen.width));

      await tester.pump(const Duration(milliseconds: 90));
      final mid = tester.getRect(find.byType(Image));
      expect(mid.width, greaterThan(early.width));

      await tester.pumpAndSettle();
      expect(find.text('detail'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('falls back for routes without an origin rect', (tester) async {
      final fallback = _RecordingBuilder();
      await tester.pumpWidget(
        _app(VideoContainerTransformBuilder(fallback: fallback)),
      );
      tester
          .state<NavigatorState>(find.byType(Navigator))
          .push(
            GetPageRoute<void>(
              page: () => const Scaffold(body: Text('detail')),
              routeName: '/detail',
              settings: const RouteSettings(name: '/detail'),
            ),
          );
      await tester.pump();
      await tester.pumpAndSettle();
      expect(fallback.calls, greaterThan(0));
      expect(find.text('detail'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });
  });
}
