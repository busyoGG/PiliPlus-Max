import 'dart:async' show Timer, StreamSubscription, unawaited;
import 'dart:convert' show jsonDecode;
import 'dart:math' as math;

import 'package:PiliPlus/common/widgets/dialog/report.dart';
import 'package:PiliPlus/common/widgets/flutter/text_field/controller.dart';
import 'package:PiliPlus/http/live.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/video.dart';
import 'package:PiliPlus/models/common/super_chat_type.dart';
import 'package:PiliPlus/models/common/video/live_quality.dart';
import 'package:PiliPlus/models/model_owner.dart';
import 'package:PiliPlus/models_new/live/live_danmaku/danmaku_msg.dart';
import 'package:PiliPlus/models_new/live/live_danmaku/live_emote.dart';
import 'package:PiliPlus/models_new/live/live_dm_info/data.dart';
import 'package:PiliPlus/models_new/live/live_medal_wall/uinfo_medal.dart';
import 'package:PiliPlus/models_new/live/live_room_info_h5/data.dart';
import 'package:PiliPlus/models_new/live/live_room_play_info/codec.dart';
import 'package:PiliPlus/models_new/live/live_room_play_info/stream.dart';
import 'package:PiliPlus/models_new/live/live_superchat/item.dart';
import 'package:PiliPlus/pages/common/publish/publish_route.dart';
import 'package:PiliPlus/pages/danmaku/danmaku_model.dart';
import 'package:PiliPlus/pages/live_room/send_danmaku/view.dart';
import 'package:PiliPlus/pages/video/widgets/header_control.dart';
import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/plugin/pl_player/models/data_source.dart';
import 'package:PiliPlus/plugin/pl_player/utils/danmaku_options.dart';
import 'package:PiliPlus/services/live_timeshift_server.dart';
import 'package:PiliPlus/services/service_locator.dart';
import 'package:PiliPlus/tcp/live.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/connectivity_utils.dart';
import 'package:PiliPlus/utils/danmaku_utils.dart';
import 'package:PiliPlus/utils/duration_utils.dart';
import 'package:PiliPlus/utils/extension/iterable_ext.dart';
import 'package:PiliPlus/utils/global_data.dart';
import 'package:PiliPlus/utils/num_utils.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:PiliPlus/utils/theme_utils.dart';
import 'package:PiliPlus/utils/utils.dart';
import 'package:PiliPlus/utils/video_utils.dart';
import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:easy_debounce/easy_throttle.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

class LiveRoomController extends GetxController {
  LiveRoomController(this.heroTag);
  final String heroTag;

  int roomId = Get.arguments;
  int? ruid;
  DanmakuController<DanmakuExtra>? danmakuController;
  final plPlayerController = PlPlayerController.getInstance(
    isLive: true,
  );

  final isLoaded = false.obs;
  final roomInfoH5 = Rxn<RoomInfoH5Data>();

  final liveTime = Rxn<int>();
  Timer? liveTimeTimer;

  void startLiveTimer() {
    if (liveTime.value != null) {
      liveTimeTimer ??= Timer.periodic(
        const Duration(minutes: 5),
        (_) => liveTime.refresh(),
      );
    }
  }

  void cancelLiveTimer() {
    liveTimeTimer?.cancel();
    liveTimeTimer = null;
  }

  Widget get timeWidget => Obx(() {
    final liveTime = this.liveTime.value;
    String text = '';
    if (liveTime != null) {
      final duration = DurationUtils.formatDurationBetween(
        liveTime * 1000,
        DateTime.now().millisecondsSinceEpoch,
      );
      text += duration.isEmpty ? '刚刚开播' : '开播$duration';
    }
    if (text.isEmpty) {
      return const SizedBox.shrink();
    }
    return Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        color: Colors.white,
      ),
    );
  });

  // dm
  LiveDmInfoData? dmInfo;
  List<RichTextItem>? savedDanmaku;
  int builtLength = 0;
  final messages = <dynamic>[].obs;
  bool get shouldRefresh => builtLength != messages.length;
  late final fsSC = Rxn<SuperChatItem>();
  late final RxList<SuperChatItem> superChatMsg = <SuperChatItem>[].obs;
  final disableAutoScroll = false.obs;
  bool autoScroll = true;
  LiveMessageStream? _msgStream;
  late final ScrollController scrollController;
  late final RxInt pageIndex = 0.obs;
  PageController? pageController;

  int? currentQn = PlatformUtils.isMobile ? null : Pref.liveQuality;
  final currentQnDesc = ''.obs;
  final RxBool isPortrait = false.obs;
  late List<({int code, String desc})> acceptQnList = [];

  late final bool isLogin;
  late final int mid;

  String? videoUrl;
  bool? isPlaying;
  late bool isFullScreen = false;

  final superChatType = Pref.superChatType;
  late final showSuperChat = superChatType != SuperChatType.disable;

  final headerKey = GlobalKey<TimeBatteryMixin>();

  final RxString title = ''.obs;

  final RxnString onlineCount = RxnString();

  final RxnString watchedShow = RxnString();
  Widget get watchedWidget => Obx(() {
    if (watchedShow.value case final watchedShow?) {
      return Text(
        watchedShow,
        style: const TextStyle(
          fontSize: 12,
          color: Colors.white,
        ),
      );
    }
    return const SizedBox.shrink();
  });

  StreamSubscription? _sizeSub;

  void _onSizeChanged((int, int) value) {
    final isVertical = value.$2 > value.$1;
    isPortrait.value = isVertical;
    plPlayerController.isVertical = isVertical;
  }

  void _startSizeSub() {
    if (isPortrait.value) return;
    _stopSizeSub();
    _sizeSub = plPlayerController.videoPlayerController?.stream.size.listen(
      _onSizeChanged,
    );
  }

  void _stopSizeSub() {
    _sizeSub?.cancel();
    _sizeSub = null;
  }

  @override
  void onInit() {
    super.onInit();
    scrollController = ScrollController()..addListener(listener);
    final account = Accounts.main;
    isLogin = account.isLogin;
    mid = account.mid;
    queryLiveUrl(autoFullScreenFlag: true);
    queryLiveInfoH5();
    if (Accounts.heartbeat.isLogin && !Pref.historyPause) {
      VideoHttp.roomEntryAction(roomId: roomId);
    }
    if (showSuperChat) {
      pageController = PageController();
    }
  }

  Future<void>? playerInit({
    bool autoplay = true,
    bool autoFullScreenFlag = false,
  }) {
    if (videoUrl == null) {
      return null;
    }
    return plPlayerController.setDataSource(
      NetworkSource(videoSource: videoUrl!, audioSource: null),
      isLive: true,
      autoplay: autoplay,
      isVertical: isPortrait.value,
      autoFullScreenFlag: autoFullScreenFlag,
    );
  }

  Future<void> queryLiveUrl({bool autoFullScreenFlag = false}) async {
    debugPrint('[LiveRoom] queryLiveUrl room=$roomId');
    currentQn ??= await ConnectivityUtils.isWiFi
        ? Pref.liveQuality
        : Pref.liveQualityCellular;
    final res = await LiveHttp.liveRoomInfo(
      roomId: roomId,
      qn: currentQn,
      onlyAudio: plPlayerController.onlyPlayAudio.value,
    );
    debugPrint('[LiveRoom] playinfo res=${res.runtimeType}');
    if (res case Success(:final response)) {
      debugPrint(
        '[LiveRoom] liveStatus=${response.liveStatus} '
        'formats=${response.playurlInfo?.playurl?.stream.map((s) => s.format.map((f) => f.formatName).toList()).toList()}',
      );
      if (response.liveStatus != 1) {
        _showDialog('当前直播间未开播');
        return;
      }
      final playurl = response.playurlInfo?.playurl;
      if (playurl == null) {
        _showDialog('无法获取播放地址');
        return;
      }
      ruid = response.uid;
      if (response.roomId case final roomId?) {
        this.roomId = roomId;
      }
      liveTime.value = response.liveTime;
      startLiveTimer();
      isPortrait.value = response.isPortrait ?? false;
      stream = playurl.stream;
      _initStreamIndex();
      await initLiveUrl(
        streamIndex: streamIndex,
        formatIndex: formatIndex,
        codecIndex: codecIndex,
        liveUrlIndex: liveUrlIndex,
      );
      isLoaded.value = true;
    } else {
      _showDialog(res.toString());
    }
  }

  late List<Stream> stream;
  int streamIndex = 0;
  int formatIndex = 0;
  int codecIndex = 0;
  int liveUrlIndex = 0;

  void _initStreamIndex() {
    final pref = Pref.liveStream;
    if (pref != null) {
      try {
        final String protocolName = pref[0];
        final String formatName = pref[1];
        final String codecName = pref[2];
        for (var (i, s) in stream.indexed) {
          if (s.protocolName == protocolName) {
            streamIndex = i;
            for (var (j, f) in s.format.indexed) {
              if (f.formatName == formatName) {
                formatIndex = j;
                for (var (k, c) in f.codec.indexed) {
                  if (c.codecName == codecName) {
                    codecIndex = k;
                    return;
                  }
                }
              }
            }
          }
        }
      } catch (_) {}
    }
  }

  /// 时移只在 fmp4(HLS) 上可用。
  ///
  /// 当前格式不是 fmp4 时，优先在同一条流里找；找不到就跨流找（例如
  /// http_stream/flv 与 http_hls/[ts, fmp4] 是两条不同的流）。
  ({int streamIndex, int formatIndex, int codecIndex}) _resolveTimeShiftSource({
    required int streamIndex,
    required int formatIndex,
    required int codecIndex,
  }) {
    ({int streamIndex, int formatIndex, int codecIndex}) current() => (
      streamIndex: streamIndex,
      formatIndex: formatIndex,
      codecIndex: codecIndex,
    );
    if (!Pref.liveTimeShift) {
      return current();
    }
    final currentFormat = stream
        .getOrNull(streamIndex)
        ?.format
        .getOrNull(formatIndex);
    final isFmp4 = currentFormat?.formatName == 'fmp4';
    if (isFmp4) {
      return current();
    }
    // 先在同一条流里找 fmp4
    final sameStream = stream
        .getOrNull(streamIndex)
        ?.format
        .indexWhere((f) => f.formatName == 'fmp4');
    if (sameStream != null && sameStream >= 0) {
      debugPrint('[LiveTimeshift] format $formatIndex -> $sameStream (fmp4)');
      return (
        streamIndex: streamIndex,
        formatIndex: sameStream,
        codecIndex: 0,
      );
    }
    // 再跨流找 fmp4
    for (var i = 0; i < stream.length; i++) {
      final formats = stream[i].format;
      final index = formats.indexWhere((f) => f.formatName == 'fmp4');
      if (index < 0) continue;
      debugPrint(
        '[LiveTimeshift] stream $streamIndex/$formatIndex -> '
        '$i/$index (fmp4)',
      );
      return (streamIndex: i, formatIndex: index, codecIndex: 0);
    }
    debugPrint('[LiveTimeshift] skipped: no fmp4 format available');
    return current();
  }

  Future<void>? initLiveUrl({
    int streamIndex = 0,
    int formatIndex = 0,
    int codecIndex = 0,
    int liveUrlIndex = 0,
  }) {
    final source = _resolveTimeShiftSource(
      streamIndex: streamIndex,
      formatIndex: formatIndex,
      codecIndex: codecIndex,
    );
    this.streamIndex = source.streamIndex;
    this.formatIndex = source.formatIndex;
    this.codecIndex = source.codecIndex;
    this.liveUrlIndex = liveUrlIndex;

    final CodecItem item = stream
        .getOrFirst(this.streamIndex)
        .format
        .getOrFirst(this.formatIndex)
        .codec
        .getOrFirst(this.codecIndex);
    // 以服务端返回的码率为准
    currentQn = item.currentQn;
    acceptQnList = item.acceptQn.map((e) {
      return (
        code: e,
        desc: LiveQuality.fromCode(e)?.desc ?? e.toString(),
      );
    }).toList();
    currentQnDesc.value =
        LiveQuality.fromCode(currentQn)?.desc ?? currentQn.toString();
    final liveUrl = VideoUtils.getLiveCdnUrl(item, index: liveUrlIndex);
    debugPrint('[LiveRoom] url qn=$currentQn ${liveUrl.split('?').first}');
    videoUrl = liveUrl;
    final timeShift = _prepareTimeShift(liveUrl);
    if (timeShift == null) {
      plPlayerController.timeShiftEnabled = false;
      return playerInit()?.whenComplete(_startSizeSub);
    }
    return timeShift.then((playlistUrl) {
      _logPlaybackState();
      videoUrl = playlistUrl ?? liveUrl;
      plPlayerController.timeShiftEnabled = playlistUrl != null;
      debugPrint(
        '[LiveTimeshift] play ${playlistUrl == null ? 'plain live' : 'local playlist'} ${playlistUrl ?? ''}',
      );
      return playerInit()?.whenComplete(() {
        _startSizeSub();
        if (playlistUrl != null) {
          _seekToLiveEdge();
        }
      });
    });
  }

  Worker? _timeShiftSeekWorker;

  Timer? _stateLogger;

  /// 打开时移房间后打印几行播放状态，便于核对进度条是否生效。
  void _logPlaybackState() {
    _stateLogger?.cancel();
    var left = 5;
    _stateLogger = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (left-- <= 0 || isClosed) {
        timer.cancel();
        return;
      }
      final p = plPlayerController;
      debugPrint(
        '[LivePlayer] pos=${p.position.value} dur=${p.duration.value} '
        'buffered=${p.buffered.value} seekEnabled=${p.seekEnabled} '
        'isLive=${p.isLive}',
      );
    });
  }

  /// 时移播放列表覆盖了最近一小时：加载后跳到直播边缘，避免从一小时前开始播。
  void _seekToLiveEdge() {
    _timeShiftSeekWorker?.dispose();
    _timeShiftSeekWorker = ever<int>(plPlayerController.duration, (duration) {
      if (duration <= 3) return;
      _timeShiftSeekWorker?.dispose();
      _timeShiftSeekWorker = null;
      debugPrint('[LiveTimeshift] live edge seek to $duration');
      Future<void>.delayed(const Duration(milliseconds: 600), () {
        if (!plPlayerController.timeShiftEnabled) return;
        unawaited(
          plPlayerController.seekTo(
            Duration(seconds: duration - 2),
            isSeek: false,
          ),
        );
      });
    });
  }

  LiveTimeshiftServer? _timeShiftServer;

  /// 收集当前播放信息里所有 fmp4(HLS) 候选地址。
  ///
  /// 时移只对 fmp4 生效，且深历史分片只存在部分 (host, path) 组合上，
  /// 所以候选越多成功率越高。
  List<String> _collectFmp4Urls(List<Stream> streams) {
    final urls = <String>[];
    final hostOverride = VideoUtils.liveCdnUrl;
    for (final s in streams) {
      for (final f in s.format) {
        if (f.formatName != 'fmp4') continue;
        for (final c in f.codec) {
          for (final ui in c.urlInfo) {
            urls.add((hostOverride ?? ui.host) + c.baseUrl + ui.extra);
          }
        }
      }
    }
    return urls;
  }

  /// 准备时移服务器；返回时移播放列表地址，null 表示走普通直播。
  Future<String?>? _prepareTimeShift(String liveUrl) {
    if (!Pref.liveTimeShift) {
      debugPrint('[LiveTimeshift] skipped: preference off');
      return null;
    }
    if (!liveUrl.contains('index.m3u8')) {
      debugPrint(
        '[LiveTimeshift] skipped: not an HLS url: ${liveUrl.split('?').first}',
      );
      return null;
    }
    final urls = <String>{liveUrl, ..._collectFmp4Urls(stream)}.toList();
    final previous = _timeShiftServer;
    _timeShiftServer = null;
    unawaited(previous?.dispose());
    final server = LiveTimeshiftServer(roomId: roomId, urls: urls);
    _timeShiftServer = server;
    debugPrint(
      '[LiveTimeshift] starting with ${urls.length} candidate urls, '
      'first: ${liveUrl.split('?').first}',
    );
    return server.start().then((ok) {
      if (!ok) {
        debugPrint('[LiveTimeshift] start failed, fallback to plain live');
        if (identical(_timeShiftServer, server)) {
          _timeShiftServer = null;
        }
        return null;
      }
      unawaited(_augmentTimeShiftSources(server));
      return server.playlistUrl;
    });
  }

  /// 多抓几次 playinfo，换出新 CDN 节点/路径，提高深历史命中率。
  Future<void> _augmentTimeShiftSources(LiveTimeshiftServer server) async {
    for (var i = 0; i < 6; i++) {
      if (!identical(_timeShiftServer, server)) return;
      final res = await LiveHttp.liveRoomInfo(roomId: roomId, qn: currentQn);
      if (res case Success(:final response)) {
        final playurl = response.playurlInfo?.playurl;
        if (playurl == null) continue;
        final urls = _collectFmp4Urls(playurl.stream);
        if (urls.isNotEmpty) server.addSources(urls);
      } else {
        return;
      }
    }
  }

  Future<void> queryLiveInfoH5() async {
    final res = await LiveHttp.liveRoomInfoH5(roomId: roomId);
    if (res case Success(:final response)) {
      roomInfoH5.value = response;
      title.value = response.roomInfo?.title ?? '';
      watchedShow.value = response.watchedShow?.textLarge;
      videoPlayerServiceHandler?.onVideoDetailChange(response, roomId, heroTag);
    } else {
      res.toast();
    }
  }

  void _showDialog(String title) {
    showDialog(
      context: Get.context!,
      builder: (_) => AlertDialog(
        title: Text(title),
        actions: [
          TextButton(
            onPressed: Get.back,
            child: Text(
              '关闭',
              style: TextStyle(color: ThemeUtils.theme.colorScheme.outline),
            ),
          ),
          TextButton(
            onPressed: () {
              if (plPlayerController.isDesktopPip) {
                plPlayerController.exitDesktopPip();
              }
              Get
                ..back()
                ..back();
            },
            child: const Text('退出'),
          ),
        ],
      ),
    );
  }

  void scrollToBottom([_]) {
    EasyThrottle.throttle(
      'liveDm',
      const Duration(milliseconds: 500),
      () => WidgetsBinding.instance.addPostFrameCallback(
        _scrollToBottom,
      ),
    );
  }

  void _scrollToBottom([_]) {
    if (scrollController.hasClients) {
      scrollController.animateTo(
        scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 500),
        curve: Curves.linearToEaseOut,
      );
    }
  }

  void handleJumpToBottom() {
    disableAutoScroll.value = false;
    if (shouldRefresh) {
      messages.refresh();
      WidgetsBinding.instance.addPostFrameCallback(_jumpToBottom);
    } else {
      _jumpToBottom();
    }
  }

  void _jumpToBottom([_]) {
    if (scrollController.hasClients) {
      scrollController.jumpTo(scrollController.position.maxScrollExtent);
    }
  }

  void closeLiveMsg() {
    _msgStream?.close();
    _msgStream = null;
  }

  @pragma('vm:notify-debugger-on-exception')
  Future<void> prefetch() async {
    final res = await LiveHttp.liveRoomDmPrefetch(roomId: roomId);
    if (res case Success(:final response)) {
      if (response != null && response.isNotEmpty) {
        messages.addAll(response);
        scrollToBottom();
      }
    } else {
      if (kDebugMode) {
        Utils.reportError(res.toString());
      }
    }
  }

  Future<void> getSuperChatMsg() async {
    final res = await LiveHttp.superChatMsg(roomId);
    if (res.dataOrNull?.list case final list?) {
      superChatMsg.addAll(list);
    }
  }

  void clearSC() {
    superChatMsg.removeWhere((e) => e.expired);
  }

  void startLiveMsg() {
    if (messages.isEmpty) {
      prefetch();
      if (showSuperChat) {
        getSuperChatMsg();
      }
    }
    if (_msgStream != null) {
      return;
    }
    if (dmInfo != null) {
      initDm(dmInfo!);
      return;
    }
    LiveHttp.liveRoomGetDanmakuToken(roomId: roomId).then((res) {
      if (res case Success(:final response)) {
        initDm(dmInfo = response);
      }
    });
  }

  void listener() {
    final userScrollDirection = scrollController.position.userScrollDirection;
    if (userScrollDirection == .forward) {
      disableAutoScroll.value = true;
    } else if (userScrollDirection == .reverse) {
      final pos = scrollController.position;
      if (pos.maxScrollExtent - pos.pixels <= 100 && disableAutoScroll.value) {
        disableAutoScroll.value = false;
        refreshMsgIfNeeded();
      }
    }
  }

  void refreshMsgIfNeeded() {
    if (shouldRefresh) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        messages.refresh();
      });
    }
  }

  @override
  void onClose() {
    _stateLogger?.cancel();
    _stateLogger = null;
    _timeShiftSeekWorker?.dispose();
    _timeShiftSeekWorker = null;
    final timeShiftServer = _timeShiftServer;
    _timeShiftServer = null;
    unawaited(timeShiftServer?.dispose());
    plPlayerController.timeShiftEnabled = false;
    _stopSizeSub();
    closeLiveMsg();
    cancelLikeTimer();
    cancelLiveTimer();
    savedDanmaku?.clear();
    savedDanmaku = null;
    messages.clear();
    if (showSuperChat) {
      superChatMsg.clear();
      fsSC.value = null;
    }
    scrollController
      ..removeListener(listener)
      ..dispose();
    pageController?.dispose();
    danmakuController = null;
    super.onClose();
  }

  // 修改画质
  Future<void>? changeQn(int qn) {
    if (currentQn == qn) {
      return null;
    }
    currentQn = qn;
    currentQnDesc.value =
        LiveQuality.fromCode(currentQn)?.desc ?? currentQn.toString();
    return queryLiveUrl();
  }

  void initDm(LiveDmInfoData info) {
    if (info.hostList.isNullOrEmpty) {
      return;
    }
    _msgStream =
        LiveMessageStream(
            streamToken: info.token,
            roomId: roomId,
            uid: Accounts.heartbeat.mid,
            servers: info.hostList
                .map((host) => 'wss://${host.host}:${host.wssPort}/sub')
                .toList(),
          )
          ..addEventListener(_danmakuListener)
          ..init();
  }

  void addDm(dynamic msg, [DanmakuContentItem<DanmakuExtra>? item]) {
    if (plPlayerController.showDanmaku) {
      if (item != null && plPlayerController.enableShowLiveDanmaku.value) {
        danmakuController?.addDanmaku(item);
      }
      if (autoScroll && !disableAutoScroll.value) {
        messages.add(msg);
        scrollToBottom();
        return;
      }
    }

    messages.addOnly(msg);
  }

  @pragma('vm:notify-debugger-on-exception')
  void _danmakuListener(dynamic obj) {
    try {
      // logger.i(' 原始弹幕消息 ======> ${jsonEncode(obj)}');
      switch (obj['cmd']) {
        case 'DANMU_MSG':
          final info = obj['info'];
          final first = info[0];
          final content = first[15];
          final Map<String, dynamic> extra = jsonDecode(content['extra']);
          final user = content['user'];
          // final midHash = first[7];
          final uid = user['uid'];
          final name = user['base']['name'];
          final msg = info[1];
          BaseEmote? uemote;
          if (first[13] case Map<String, dynamic> map) {
            uemote = BaseEmote.fromJson(map);
          }
          final checkInfo = info[9];
          final liveExtra = LiveDanmaku(
            id: extra['id_str'],
            mid: uid,
            dmType: extra['dm_type'],
            ts: checkInfo['ts'],
            ct: checkInfo['ct'],
          );
          Owner? reply;
          final replyMid = extra['reply_mid'];
          if (replyMid != null && replyMid != 0) {
            reply = Owner(
              mid: replyMid,
              name: extra['reply_uname'],
            );
          }
          addDm(
            DanmakuMsg(
              name: name,
              text: msg,
              emots: (extra['emots'] as Map<String, dynamic>?)?.map(
                (k, v) => MapEntry(k, BaseEmote.fromJson(v)),
              ),
              uemote: uemote,
              extra: liveExtra,
              reply: reply,
              medalInfo: !GlobalData().showMedal || user['medal'] == null
                  ? null
                  : UinfoMedal.fromJson(user['medal']),
            ),
            DanmakuContentItem(
              msg,
              color: DanmakuOptions.blockColorful
                  ? Colors.white
                  : DmUtils.decimalToColor(extra['color']),
              type: DmUtils.getPosition(extra['mode']),
              // extra['send_from_me'] is invalid
              selfSend: isLogin && uid == mid,
              extra: liveExtra,
            ),
          );
          break;
        case 'SUPER_CHAT_MESSAGE' when showSuperChat:
          final item = SuperChatItem.fromJson(obj['data']);
          superChatMsg.insert(0, item);
          if (plPlayerController.showDanmaku &&
              (isFullScreen || plPlayerController.isDesktopPip)) {
            fsSC.value = item.copyWith(
              endTime: math.min(
                item.endTime,
                DateTime.now().millisecondsSinceEpoch ~/ 1000 + 10,
              ),
            );
          }
          addDm(item);
          break;
        // case 'SUPER_CHAT_MESSAGE_DELETE' when showSuperChat:
        //   if (obj['roomid'] == roomId) {
        //     final ids = obj['data']?['ids'] as List?;
        //     if (ids != null && ids.isNotEmpty) {
        //       if (superChatType == .valid) {
        //         superChatMsg.removeWhere((e) => ids.contains(e.id));
        //       } else {
        //         bool? refresh;
        //         for (final id in ids) {
        //           if (superChatMsg.firstWhereOrNull((e) => e.id == id)
        //               case final item?) {
        //             item.deleted = true;
        //             refresh ??= true;
        //           }
        //         }
        //         if (refresh ?? false) {
        //           superChatMsg.refresh();
        //         }
        //       }
        //     }
        //   }
        case 'WATCHED_CHANGE':
          watchedShow.value = obj['data']['text_large'];
          break;
        case 'ONLINE_RANK_COUNT':
          onlineCount.value = NumUtils.numFormat(obj['data']['count']);
          break;
        case 'ROOM_CHANGE':
          title.value = obj['data']['title'];
          break;
      }
    } catch (e, s) {
      if (kDebugMode) {
        Utils.reportError(e, s);
      }
    }
  }

  final RxInt likeClickTime = 0.obs;
  Timer? likeClickTimer;

  void cancelLikeTimer() {
    likeClickTimer?.cancel();
    likeClickTimer = null;
  }

  void onLikeTapDown([_]) {
    cancelLikeTimer();
    likeClickTime.value++;
  }

  void onLikeTapUp([_]) {
    likeClickTimer ??= Timer(
      const Duration(milliseconds: 800),
      onLike,
    );
  }

  Future<void> onLike() async {
    if (!isLogin) {
      likeClickTime.value = 0;
      return;
    }
    final res = await LiveHttp.liveLikeReport(
      clickTime: likeClickTime.value,
      roomId: roomId,
      uid: mid,
      anchorId: roomInfoH5.value?.roomInfo?.uid,
    );
    if (res.isSuccess) {
      SmartDialog.showToast('点赞成功');
    } else {
      res.toast();
    }
    likeClickTime.value = 0;
  }

  void onSendDanmaku([bool fromEmote = false]) {
    if (kReleaseMode && !isLogin) {
      SmartDialog.showToast('账号未登录');
      return;
    }
    Get.key.currentState!.push(
      PublishRoute(
        barrierColor: Colors.transparent,
        pageBuilder: (context, animation, secondaryAnimation) {
          return Theme(
            data: ThemeUtils.darkTheme,
            child: LiveSendDmPanel(
              fromEmote: fromEmote,
              liveRoomController: this,
              items: savedDanmaku,
              autofocus: !fromEmote,
              onSave: (msg) {
                if (msg.isEmpty) {
                  savedDanmaku?.clear();
                  savedDanmaku = null;
                } else {
                  savedDanmaku = msg.toList();
                }
              },
            ),
          );
        },
        transitionDuration: fromEmote
            ? const Duration(milliseconds: 400)
            : const Duration(milliseconds: 500),
      ),
    );
  }

  void reportSC(SuperChatItem item) {
    if (!isLogin) {
      SmartDialog.showToast('账号未登录');
      return;
    }
    autoWrapReportDialog(
      Get.context!,
      ban: false,
      ReportOptions.liveDanmakuReport,
      (reasonType, reasonDesc, banUid) {
        return LiveHttp.superChatReport(
          id: item.id,
          roomId: roomId,
          uid: item.uid,
          msg: item.message,
          reason: ReportOptions.liveDanmakuReport['']![reasonType]!,
          ts: item.ts,
          token: item.token,
        );
      },
    );
  }
}
