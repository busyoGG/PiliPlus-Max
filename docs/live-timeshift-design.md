# 直播时移（进度条拖拽）实现说明

状态：已实现（v1）
日期：2026-11-18
相关房间实测：7734200（B 站英雄联盟赛事 24h 轮播）

## 1. 目标

让直播间的进度条可以往回拖。官方 App 在赛事房间已有该能力，回看窗口约 1 小时。

## 2. 机制事实（实测确认）

B 站直播 playurl 返回的 **fmp4 HLS** 地址支持 `tmshift` 查询参数：

```
https://<host>/live-bvc/<streamId>/live_<roomId>_bs_<id>/index.m3u8?expires=...&qn=10000&...&tmshift=1200
```

1. `tmshift=N` 返回「当前时刻 - N 秒」为锚点的窗口，`#EXT-X-MEDIA-SEQUENCE` 精确后退 N。
2. 签名参数 `sigparams=cdn,expires,len,oi,pt,qn,trid,bmt` **不覆盖** tmshift，可任意改写。
3. 分片名是纯递增数字 `<seq>.m4s`，1 分片 = 1 秒，seq 与时间线性对应；seq 带 epoch 前缀（实测见过 `427...` 与 `527...`）。
4. `ts` 版 HLS（3 秒分片）与 FLV **完全忽略** tmshift，只有 fmp4 支持。
5. 保留期实测：`tmshift=4500`（75 分钟）可下，`5400`（90 分钟）全灭 → 服务端保留约 60~75 分钟。
6. 深历史分片只存在于部分 `(host, path)` 组合，同一分片在多数组合上 404 → 需要组合池 + 轮询重试。
7. 未登录的 `web-room/v2/index/getRoomPlayInfo` 就能拿到可用的 fmp4 地址（`codec[].url_info` 即是 host 列表）。

## 3. 架构

```
playinfo(fmp4) ──┐
                 ├─> LiveTimeshiftServer（Dart HttpServer，127.0.0.1 随机端口）
直播 playlist ────┘        ├─ /index.m3u8   动态生成的 EVENT 播放列表
                           ├─ /<seq>.m4s    取片：本地缓存 → CDN 组合轮询 → 404
                           └─ /init.m4s     EXT-X-MAP 初始化段
                                   │
                        mpv (media_kit) 播放并 seek
```

播放列表是 `#EXT-X-PLAYLIST-TYPE:EVENT`，长度 = 已播出的时移窗口，因此播放器拿到的 `duration` 就是可回看总长（实测 ffprobe `duration=3596`），进度条自然出现。

## 4. 关键实现细节

| 点 | 做法 | 为什么 |
| --- | --- | --- |
| 窗口起点 | `_probeWindowStart()` 依次试 `tmshift=3600/1800/900/300/60`，用第一个能取到分片的作为起点 | 保留期因组合而异，写死 1 小时会导致起播分片 404 |
| 安全边缘 | `_safeEdge = liveSeq - 5` | CDN 最新 1~2 个分片常常还没写完 |
| 分片校验 | `_looksLikeFmp4()`：长度 < 1024 或 box 类型不在 `styp/moof/moov/sidx/ftyp/emsg/free` 内则丢弃 | CDN 异常时会 200 返回错误页 |
| 组合池 | 来自 playinfo 的 `url_info`，启动后再异步补 6 次 playinfo 扩充 | 深分片只在部分组合上存在 |
| 选组合 | 只考虑 `_sourceSeq` 与当前 `_liveSeq` 相差 ±120 以内的源，命中即标记 hot | 避免拿过期/无效的 host |
| 本地缓存 | 每片回源成功后写盘 `live_dvr/<roomId>/<epoch>/<seq>.m4s`，环形淘汰 | 暂停/回拖不再重复回源；CDN 拿不到的区间靠它兜底 |
| 降级 | 拿不到 fmp4 或 `start()` 失败 → `videoUrl` 用原地址、`timeShiftEnabled=false` | 不影响普通直播 |
| 进度条解锁 | `PlPlayerController.seekEnabled => !isLive || timeShiftEnabled`，view 层门禁改用它 | 直播默认仍禁拖，时移房间才放开 |
| 起播位置 | `_watchTimeShiftPlayback()`：起播后 20 秒内，只要播放位置 < 30s 就按需 seek 到 `窗口长度 - 3s`（最多 4 次、间隔 3s），位置正常后停止；判定逻辑抽到纯函数 `timeShiftAdoptTarget()` | 安卓 mpv 起播时音频 underrun 会把播放位置重启到窗口最早的分片，表现为「打开直播停在一小时前」 |

## 5. 验证记录

离线单测 `test/services/live_timeshift_server_test.dart`（本地假 CDN，8 个用例）：地址解析、seq 校准、播放列表覆盖窗口、越界 404、缓存命中、窗口滑动、seq 跳变重建、固定窗口长度。

离线单测 `test/services/live_timeshift_start_test.dart`（7 个用例）：起播位置判定（已在边缘不干预、窗口过短不干预、停在开头时拉到边缘、重试上限、保护期、跳转间隔）。合计 15 个用例全部通过。

PC 端真实 CDN 端到端（真实 playinfo + LiveTimeshiftServer + 外部播放器）：

| 用例 | 结果 |
| --- | --- |
| 播放列表自检 | 200，7200 行，3600 个分片 |
| `ffmpeg -ss 1200` 跳 20 分钟 | exit 0 |
| `ffprobe` duration | 3596.0 |
| `mpv --start=1200` | exit 0，状态行 `AV: 00:20:02 / 01:00:01` |
| `ffmpeg` 从直播边缘连续播 25 秒 | exit 0，按 0.5s 循环刷新列表并连续取新片 |

## 6. 改动文件

| 文件 | 改动 |
| --- | --- |
| `lib/services/live_timeshift_server.dart`（新） | HttpServer：EVENT 播放列表、窗口探测、组合池、分片代理与校验、降级 |
| `lib/services/live_dvr_cache.dart`（新） | 分片写盘、环形淘汰、按 seq 查询 |
| `lib/services/live_timeshift_start.dart`（新） | 起播位置判定纯函数 `timeShiftAdoptTarget()` |
| `lib/pages/live_room/controller.dart` | `_prepareTimeShift` / `_augmentTimeShiftSources` / `_watchTimeShiftPlayback` / `_logPlaybackState`，`initLiveUrl` 走本地列表，`onClose` 清理 |
| `lib/plugin/pl_player/controller.dart` | `timeShiftEnabled`、`seekEnabled` |
| `lib/plugin/pl_player/view/view.dart` | 拖拽/双击/进度条/快进快退等门禁由 `isLive` 改为 `seekEnabled` |
| `lib/utils/storage_key.dart`、`storage_pref.dart`、`default_settings.dart` | 开关 `liveTimeShift`，默认开 |
| `lib/pages/setting/models/video_settings.dart` | 设置项「直播时移（进度条）」 |
| `test/services/live_timeshift_server_test.dart`（新） | 离线单测 |
| `test/services/live_timeshift_start_test.dart`（新） | 起播位置判定单测 |

## 7. 已知边界与风险

1. 时移深度受服务端保留期限制（约 60~75 分钟），并非无限。
2. 深分片命中率不稳定（缓存驱逐、组合漂移）→ 已用重试 + 缓存 + 404 降级处理。
3. 拖动会拉取历史分片，带宽与直播相当，弱网下可能缓冲。
4. 多组合并发回源可能触发风控，已限并发、复用普通请求头。
5. 普通主播房是否开启 tmshift 未逐一验证；未开启时自动降级为普通直播。
6. 码率切换（换 qn）后 seq 是否连续未验证；重建窗口逻辑可兜底但会清空回看深度。
7. 本地缓存默认 400 MB / 3600 片，退出房间清空。
8. 起播位置兜底依赖播放器与本地服务时序：若设备在 20 秒保护期内仍未回到直播边缘，进度条会停在窗口起点，重新进房即可恢复。
