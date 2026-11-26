/// 直播 PK 对方主播信息。
///
/// 直播间弹幕流里的 PK_BATTLE_* / PK_BATTLE_FINAL_PROCESS 消息字段各不相同：
/// PRE/START 带 room_id/uname/face，PROCESS 只带票数，因此解析时容错取值，
/// 缺字段时保留上一份数据。
class PkBattleInfo {
  const PkBattleInfo({
    this.pkId,
    this.status,
    this.uid,
    this.roomId,
    this.uname,
    this.face,
    this.endTime,
  });

  final int? pkId;
  final int? status;
  final int? uid;
  final int? roomId;
  final String? uname;
  final String? face;
  final int? endTime;

  /// PK 已结束（官方 status: 1 准备 2 开始 3 进行 4 结束 5 结算）。
  bool get isEnded => status != null && status! >= 4;

  PkBattleInfo merge(PkBattleInfo? previous) {
    if (previous == null) return this;
    return PkBattleInfo(
      pkId: pkId ?? previous.pkId,
      status: status ?? previous.status,
      uid: uid ?? previous.uid,
      roomId: roomId ?? previous.roomId,
      uname: (uname != null && uname!.isNotEmpty) ? uname : previous.uname,
      face: (face != null && face!.isNotEmpty) ? face : previous.face,
      endTime: endTime ?? previous.endTime,
    );
  }

  factory PkBattleInfo.fromJson(Map<String, dynamic> json) {
    final Object? raw = json['data'];
    final Map<String, dynamic> data = raw is Map<String, dynamic> ? raw : json;
    Object? pick(String key) => data[key] ?? json[key];
    int? toInt(Object? value) => switch (value) {
      final int v => v,
      final String v => int.tryParse(v),
      final num v => v.toInt(),
      _ => null,
    };
    return PkBattleInfo(
      pkId: toInt(pick('pk_id')),
      status: toInt(pick('pk_status')),
      uid: toInt(pick('uid')),
      roomId: toInt(pick('room_id')),
      uname: pick('uname') as String?,
      face: pick('face') as String?,
      endTime: toInt(pick('end_time')),
    );
  }
}