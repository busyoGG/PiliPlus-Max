# 同步上游 PiliPlus 计划（2.1.0 → 2.2.0）

## 结论与选型
- 目标上游：**PiliPlus 2.2.0**（commit `265f879fa`）。2.2.1（`217fb54f5`）上游自身在发布依赖下编译不过
  （`lib/utils/request_utils.dart` 用了 `MediaQuery.shortestSideOf`，`dyn_tab_bar/bottom_sheet/draggable_sheet`
  用了 material_ui 未导出的类型，analyze 159 error），所以不作为同步目标。
- 工具链：Flutter **3.47.9**（`.fvmrc` + `pubspec.yaml` 的 `flutter:` 都必须是 3.47.9），AGP 9.1.0。
- 基线文件清单：2.2.0 相对 2.1.0 改动 **905 个文件**；PiliPlus-Max 相对 2.1.0 改动 **285 个文件**；
  交集 **179 个文件**（这些必须逐个人工移植）。

## 分支
| 分支 | 用途 |
| --- | --- |
| `mod` | 线上可用版本（3.2.0+13，Flutter 3.44.8） |
| `backup/pre-merge-3.2` | 同步前快照 |
| `sync/2.2.0` | 同步工作分支，当前 = 干净上游 2.2.0，analyze 0 error |

## 迁移顺序（每步都要 analyze + 相关测试 + 真机装包）
1. **版本与配置**：`pubspec.yaml` version 3.3.0+14、`lib/build_config.dart` '3.3'、
   `android/app/build.gradle.kts` versionName 跟 pubspec、`.fvmrc` 3.47.9。
2. **界面毛玻璃**：新增 `lib/common/widgets/blur/app_blur.dart`（BlurSurface/FrostedOval/`_OuterShadowPainter`/阴影常量）；
   接入 `home/view.dart`、`dynamics/view.dart`、`main/view.dart`、`floating_navigation_bar.dart`、
   `common/widgets/flutter/refresh_indicator.dart`（edgeOffset + FrostedOval）、设置页开关（uiBlur/uiBlurEnabled）。
   ⚠️ 上游 2.2.0 已把 material 换到 `package:material_ui`，我们的 `flutter/*` 自维护控件版本较旧，
   移植时以**上游版本为底**，只把我们新增的参数/逻辑贴进去。
3. **卡片转场 + 预测性返回**：新增 `page_transition/video_container_transform.dart`；
   `lib/utils/theme_utils.dart` 里 Android 用 `VideoCardPageTransitionsBuilder`；
   `lib/scripts/getx_predictive_back.patch`（getx 本地补丁，需重新 apply 到新 pub 缓存）；
   `AndroidManifest.xml` `enableOnBackInvokedCallback="true"`；卡片入口传 `originRect`。
4. **视频比例修复**：新增 `pl_player/widgets/display_aspect_video.dart` + `video_fit_type.dart` 的
   `resolveVideoBoxAspect`，并在上游新的 `pl_player/view/view.dart` 非 mpv 分支替换 `SimpleVideo`。
5. **直播时移 / 本地 DVR / 起播优化**（最难，上游重写 `pl_player/controller.dart` 725 行、
   `live_room/controller.dart`）：
   - 服务层整体搬：`lib/services/live_timeshift_server.dart`、`live_timeshift_start.dart`、`live_dvr_cache.dart`；
   - 播放器层：`timeShiftEnabled/timeShiftSeek/timeShiftDuration/timeShiftPositionBase` + `seekEnabled`，
     以及 view 里所有 `isLive` 门改为 `seekEnabled`；
   - 直播页：`_resolveTimeShiftSource/_prepareTimeShift/_applyTimeShiftTimeline/_enableTimeShift/_restartAtTimeShift/
     _watchTimeShiftPlayback/_augmentTimeShiftSources/playPlainLive`；
   - 设置：`liveTimeShift` 开关 + 文案；
   - 起播优化：`ConnectivityUtils` 缓存与 `warmUp()`、`main.dart` 预热、augment 延迟。
6. **赛事赛程入口**：`http/match.dart` + `api.dart` 常量 + `models_new/match/**` + `utils/esports_utils.dart` +
   `pages/live_room/widgets/esports_schedule_sheet.dart` + `bottom_control.dart` 按钮 + H5 roomInfo 的
   `areaId/parentAreaId/isEsportsArea`。
7. **杂项修复**：返回时抑制 toast（`account_mgr.dart` + `video/controller.dart` 的 `_exiting/_routeLeaving`）、
   `startup_log.dart` 编译期开关、首页顶栏收起不重建 `home/view.dart`、进度条拖动
   （`audio_video_progress_bar.dart` 的 `onDragStart`）、底栏阴影、`Style.topBarHeight`、状态栏占位布局。

## 验证
- `fvm flutter analyze <改动文件>` 必须 0 issue（全库 analyze 允许上游自带的死文件报错）。
- `fvm flutter test test/services test/utils test/pages/live_room test/common/widgets/video_container_transform_test.dart`。
- 构建：`export ANDROID_HOME=/opt/android-sdk ANDROID_SDK_ROOT=/opt/android-sdk && fvm flutter build apk --release --target-platform android-arm64`。
- 装包：`adb install -r --no-streaming build/app/outputs/flutter-apk/app-release.apk`。
- 全部通过后 `git checkout mod && git merge --no-ff sync/2.2.0`（冲突一律取 sync 侧），再推 `origin mod`。

## 风险
- 上游 2.2.x 把 material 全面迁到 `material_ui`，我们 3.44.8 时代的 `lib/common/widgets/flutter/*` 拷贝
  不能直接复用——必须以上游新版为底，只贴我们的改动，否则会重演「两万条编译错误」。
- `pl_player` 被上游大改，时移/比例修复需要按新结构重贴，不能整文件覆盖。
