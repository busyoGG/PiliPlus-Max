# 直播时移（进度条拖拽）实现说明

赛事类直播间（如 <https://live.bilibili.com/7734200>）在官方客户端里可以拖动进度条回看。
本文记录 PiliPlus-Max 的实现方式与验证结论。

## 1. 目标

- 赛事直播播放时，进度条可用、可拖动，回看深度接近官方（约 1 小时）。
- 普通直播间行为不变；功能可关闭，关闭后完全走原有直播链路。
- 失败必须自动降级为普通直播，不能出现「直播加载不出来」。

## 2. 机制事实（实测确认）

- 官方 app 的播放地址里带 tmshift=<秒> 参数，播放器解析后交给 P2P 层，服务端按该偏移返回历史分片。
- CDN 的 fmp4 播放列表是 1 秒一个分片的滑动窗口，&tmshift=N 可让窗口整体后退 N 秒；签名参数
  （sigparams=cdn,expires,len,oi,pt,qn,trid,bmt）不覆盖 tmshift，所以可以自由改写。
- 分片文件名就是 <seq>.m4s，seq 带 epoch 前缀；分片可以按 seq 直接取，但必须带同样的 tmshift，
  否则 CDN 返回 404（相对路径不会继承播放列表的 query）。
- 只有 format_name=fmp4 的流支持时移，ts 流忽略 tmshift。
- 可回看深度与 (host, path) 组合有关，实测约 60~75 分钟；同一时刻只有部分 host/path 能取到历史分片。
- 直接把 CDN 地址交给 mpv 播不了（分片相对路径丢参数），所以必须经过本地代理重新拼 query。

## 3. 架构

- 播放器（mpv）只播本机回环地址上的「短窗口播放列表」，形如 http://127.0.0.1:<port>/index.m3u8：
  固定 6 个 1 秒分片，EXT-X-PLAYLIST-TYPE:EVENT。分片请求由本地服务按 seq 反查 CDN，自动补上 tmshift。
- 拖动进度条不移动播放器时间线，而是改写「窗口偏移」并重启本地播放列表
  （与官方重启式 seek 一致）。播放器始终在列表末端附近播放，CDN 侧回退到目标时间。
- 进度条的时间线在 Dart 侧虚拟出来：时长 = 可回看深度，显示位置 = 播放器位置 + 偏移。

## 4. 关键实现细节

- lib/services/live_timeshift_server.dart：本地 HLS 代理。
  - _probeRetention() 并发探测 3600/2700/…/120 秒的深度，命中即定为可回看深度（3 个候选源、6 秒超时）。
    探测在起播之后后台进行，不阻塞首帧；同一房号探测结果会记住，二次进入直接用缓存深度、不再探测。
  - baseOffset 表示窗口相对直播边缘的后退秒数；播放列表覆盖 [live - baseOffset - playlistSpan, live - baseOffset - 1]。
  - onWindowChanged 回调把深度变化通知业务层刷新时间线。
- lib/services/live_dvr_cache.dart：分片本地缓存（环形淘汰，默认 400MB / 3600 片），拖动过的分片再次播放不再回源。
- lib/plugin/pl_player/controller.dart：
  - timeShiftEnabled（RxBool）驱动 seekEnabled = !isLive || timeShiftEnabled.value，UI 据此显示进度条。
  - timeShiftDuration 覆盖进度条长度；timeShiftPositionBase 把播放器位置映射到窗口位置；
    timeShiftSeek 拦截 seekTo，直播时移下改为重启式定位。
- lib/pages/live_room/controller.dart：
  - initLiveUrl 先申请时移服务，成功才切到 fmp4 码流；任何失败（关闭开关、非 HLS、取列表失败、启动异常）
    都回滚到原码流播放普通直播。
  - _applyTimeShiftTimeline 计算时间线；_onTimeShiftSeek 改写 baseOffset 并重启播放列表。
- lib/plugin/pl_player/view/view.dart：进度条、双击快进、横向拖动的开关从 isLive 改为 seekEnabled，
  并监听 timeShiftEnabled 变化后 setState，保证进度条能及时出现。

## 5. 验证记录

- 单元测试：test/services/live_timeshift_server_test.dart（短窗口 / 偏移 / 缓存 / 404 / 窗口滑动 / 换流重建）、
  test/services/live_timeshift_start_test.dart（起播位置判定）共 16 项，fvm flutter test test/services 全绿。
- PC mpv（0.41 / FFmpeg n9.0.2）：对本地代理列表 duration≈3600，7 个偏移点 seek 全部精确命中。
- 设备（OnePlus 13 / Android 14）：logcat 可见 可回看 back=3600 -> ready seq=… window=3600
  -> pos=3594 dur=3600 seekEnabled=true，进度条时间线与直播边缘对齐。

## 6. 改动文件

- lib/services/live_timeshift_server.dart、lib/services/live_dvr_cache.dart、lib/services/live_timeshift_start.dart
- lib/plugin/pl_player/controller.dart、lib/plugin/pl_player/view/view.dart
- lib/pages/live_room/controller.dart
- lib/utils/storage_key.dart、lib/utils/storage_pref.dart、lib/utils/default_settings.dart、
  lib/pages/setting/models/video_settings.dart
- test/services/live_timeshift_server_test.dart、test/services/live_timeshift_start_test.dart

## 7. 已知边界与风险

- 深度探测受网络影响：探测失败时保守按 60 秒处理，进度条只显示 1 分钟。
- 回看分片只存在于部分 host/path，拖动到较深位置可能需要几次重试才能出画。
- 拖动会重启播放列表，画面会有一次短暂重建（与官方重启式 seek 相同）。
- 部分主播/普通直播间不提供 fmp4 或时移，自动降级为普通直播。
- 本地服务绑定 127.0.0.1 随机端口，不监听外部地址。
