import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:PiliPlus/common/widgets/blur/app_blur.dart';

Widget _app(Widget child) => MaterialApp(
  home: Scaffold(
    body: Stack(children: <Widget>[const ColoredBox(color: Colors.red), child]),
  ),
);

void main() {
  group('AppBlur', () {
    test('sigma is zero when blur is disabled', () {
      expect(AppBlurStrength.off.scale, 0);
      expect(AppBlurStrength.light.scale, 1);
      expect(AppBlurStrength.heavy.scale, 2);
    });

    test('keeps bar sigma constants aligned with the design', () {
      expect(AppBlur.barSigma, 12);
      expect(AppBlur.playerBarSigma, 18);
      expect(AppBlur.sheetSigma, 24);
    });
  });

  group('BlurSurface', () {
    testWidgets('falls back to the plain child when blur is off', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _app(
          const BlurSurface(
            strength: AppBlurStrength.off,
            plainChild: Text('plain'),
            child: Text('blurred'),
          ),
        ),
      );
      expect(find.text('plain'), findsOneWidget);
      expect(find.byType(BackdropFilter), findsNothing);
    });

    testWidgets('wraps the child in a backdrop filter when enabled', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _app(
          const BlurSurface(
            strength: AppBlurStrength.light,
            child: Text('blurred'),
          ),
        ),
      );
      final Finder filter = find.byType(BackdropFilter);
      expect(
        filter,
        findsOneWidget,
      );
      final BackdropFilter widget = tester.widget<BackdropFilter>(filter);
      expect(widget.filter, isNotNull);
      expect(find.text('blurred'), findsOneWidget);
    });

    testWidgets('always clips to its own bounds so the backdrop stays local', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _app(
          const BlurSurface(
            strength: AppBlurStrength.light,
            borderRadius: BorderRadius.all(Radius.circular(16)),
            child: Text('rounded'),
          ),
        ),
      );
      expect(find.byType(ClipRRect), findsOneWidget);
    });

    testWidgets('clips even without a radius', (WidgetTester tester) async {
      await tester.pumpWidget(
        _app(
          const BlurSurface(
            strength: AppBlurStrength.light,
            child: Text('square'),
          ),
        ),
      );
      expect(find.byType(ClipRRect), findsOneWidget);
    });
  });
}
