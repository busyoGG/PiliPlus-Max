import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

/// Records whether the host app theme was consulted for the Android page
/// transition. Keeping this green means [GetPageRoute] keeps delegating its
/// transition to `ThemeData.pageTransitionsTheme` (see
/// `lib/scripts/getx_predictive_back.patch`), which is what makes
/// `PredictiveBackPageTransitionsBuilder` reach the app on Android 14+.
class _RecordingPageTransitionsBuilder extends PageTransitionsBuilder {
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

ThemeData _theme(PageTransitionsBuilder builder) => ThemeData(
  pageTransitionsTheme: PageTransitionsTheme(
    builders: {for (final platform in TargetPlatform.values) platform: builder},
  ),
);

Widget _app({required ThemeData theme}) => GetMaterialApp(
  theme: theme,
  defaultTransition: Transition.native,
  initialRoute: '/',
  getPages: [
    GetPage(name: '/', page: () => const Scaffold(body: Text('home'))),
    GetPage(name: '/next', page: () => const Scaffold(body: Text('next'))),
  ],
);

/// Feeds a predictive back gesture event through the same platform channel the
/// Android engine uses.
Future<void> _sendBackGesture(
  TestWidgetsFlutterBinding binding,
  String method, [
  Map<String, Object?>? arguments,
]) async {
  await binding.defaultBinaryMessenger.handlePlatformMessage(
    SystemChannels.backGesture.name,
    SystemChannels.backGesture.codec.encodeMethodCall(
      MethodCall(method, arguments),
    ),
    (_) {},
  );
}

Map<String, Object?> _event(double progress) => <String, Object?>{
  'touchOffset': <double>[progress * 400, 800],
  'progress': progress,
  'swipeEdge': 0,
};

void main() {
  testWidgets('GetX native transition follows PageTransitionsTheme', (
    tester,
  ) async {
    final builder = _RecordingPageTransitionsBuilder();

    await tester.pumpWidget(_app(theme: _theme(builder)));
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);

    Get.toNamed('/next');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(builder.calls, greaterThan(0));
    await tester.pumpAndSettle();
    expect(find.text('next'), findsOneWidget);
  });

  testWidgets('predictive back gesture scales the current page', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(theme: _theme(const PredictiveBackPageTransitionsBuilder())),
    );
    await tester.pumpAndSettle();
    Get.toNamed('/next');
    await tester.pumpAndSettle();

    final before = tester.getRect(find.text('next'));

    await _sendBackGesture(tester.binding, 'startBackGesture', _event(0.0));
    await _sendBackGesture(
      tester.binding,
      'updateBackGestureProgress',
      _event(0.4),
    );
    await tester.pump();

    final during = tester.getRect(find.text('next'));
    expect(during.width, lessThan(before.width * 0.99));
    expect(during.left, isNot(closeTo(before.left, 0.5)));

    await _sendBackGesture(tester.binding, 'cancelBackGesture');
    await tester.pumpAndSettle();
    expect(find.text('next'), findsOneWidget);
    expect(tester.getRect(find.text('next')).width, closeTo(before.width, 1));
    expect(tester.getRect(find.text('next')).left, closeTo(before.left, 1));
  });
}
