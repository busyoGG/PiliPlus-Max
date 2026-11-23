import 'package:PiliPlus/common/skeleton/skeleton.dart';
import 'package:PiliPlus/utils/utils.dart';
import 'package:material_ui/material_ui.dart';

class SpaceOpusSkeleton extends StatelessWidget {
  const SpaceOpusSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final surface = ColorScheme.of(context).onInverseSurface;
    return Skeleton(
      child: Card(
        clipBehavior: Clip.hardEdge,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height:
                      (0.68 + 0.82 * Utils.random.nextDouble()) *
                      constraints.maxWidth,
                  color: surface,
                ),
                Container(
                  height: 10,
                  color: surface,
                  margin: const EdgeInsets.all(10),
                  width: constraints.maxWidth * 0.7,
                ),
                Container(
                  height: 10,
                  color: surface,
                  borderRadius: const .vertical(top: .circular(6)),
                ),
              ),
            ),
            FractionallySizedBox(
              widthFactor: 0.7,
              alignment: .topLeft,
              child: Container(
                height: 10,
                color: surface,
                margin: const .all(10),
              ),
            ),
            Container(
              height: 10,
              color: surface,
              margin: const .only(left: 10, right: 10, bottom: 10),
            ),
          ],
        ),
      ),
    );
  }
}
