import 'package:PiliPlus/models/common/enum_with_label.dart';

enum BtmProgressBehavior with EnumWithLabel {
  alwaysShow('始终展示'),
  alwaysHide('始终隐藏'),
  onlyShowFullScreen('仅全屏时展示'),
  onlyHideFullScreen('仅全屏时隐藏'),
  ;

  final String desc;

  @override
  String get label => desc;
  const BtmProgressBehavior(this.desc);
}
