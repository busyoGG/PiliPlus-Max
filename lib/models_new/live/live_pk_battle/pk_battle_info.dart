/// 直播 PK 对方主播信息。
///
/// 直播间弹幕流里的 PK_BATTLE_* / PK_BATTLE_FINAL_PROCESS 消息字段各不相同：
/// PRE/START 带 room_id/uname/face，PROCESS 只带票数，因此解析时容错取值，
/// 缺字段时保留上一份数据。
int? pickInt(Object? value) => switch (value) {
  final int v => v,
  final String v => int.tryParse(v),
  final num v => v.toInt(),
  _ => null,
};

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
    // 消息体可能是顶层字段、data 包裹，或 data.pk_battle_info / pk_info 再包一层。
    Map<String, dynamic> asMap(Object? value) => switch (value) {
      final Map<String, dynamic> map => map,
      final Map<dynamic, dynamic> map => map.map(
        (key, value) => MapEntry(key.toString(), value),
      ),
      _ => const <String, dynamic>{},
    };
    Map<String, dynamic> data = asMap(json['data']);
    for (final String key in const <String>['pk_battle_info', 'pk_info']) {
      final Map<String, dynamic> nested = asMap(data[key]);
      if (nested.isNotEmpty) {
        data = nested;
        break;
      }
    }
    if (data.isEmpty) {
      data = json;
    }
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

  /// PK_INFO（多人连麦/PK）消息里的对方主播。
  static PkBattleInfo? fromPkInfo(
    Map<String, dynamic> json, {
    int? selfUid,
  }) {
    final Object? rawData = json['data'];
    final Map<dynamic, dynamic> data = rawData is Map ? rawData : json;
    final Object? rawMembers = data['members'] ?? json['members'];
    if (rawMembers is! List || rawMembers.isEmpty) {
      return null;
    }
    for (final Object? raw in rawMembers) {
      if (raw is! Map) continue;
      final Map<String, dynamic> member = raw.map(
        (key, value) => MapEntry(key.toString(), value),
      );
      final int? uid = pickInt(member['uid']);
      if (selfUid != null && uid == selfUid) {
        continue;
      }
      final int? roomId = pickInt(member['room_id']);
      if (uid == null && roomId == null) {
        continue;
      }
      return PkBattleInfo(
        status: 2,
        uid: uid,
        roomId: roomId,
        uname: member['uname'] as String?,
        face: member['face'] as String?,
      );
    }
    return null;
  }
}