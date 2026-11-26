/// 直播 PK / 多人连麦里的连线对象信息。
///
/// 数据来源有两个：
/// 1. 弹幕 `PK_INFO`，形如 {"cmd":"PK_INFO","data":{"members":[...],"pk_basic":{...}}}；
/// 2. 官方接口 /xlive/general-interface/v2/pk/info，data 结构与上面完全一致。
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
    this.votes,
  });

  final int? pkId;
  final int? status;
  final int? uid;
  final int? roomId;
  final String? uname;
  final String? face;
  final int? endTime;
  final int? votes;

  /// 已结束以官方给的 end_time 为准（status 各业务线取值不统一，601 也属于进行中）。
  bool get isEnded {
    final int? end = endTime;
    if (end == null || end <= 0) {
      return false;
    }
    return DateTime.now().millisecondsSinceEpoch ~/ 1000 >= end;
  }

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
      votes: votes ?? previous.votes,
    );
  }

  factory PkBattleInfo.fromJson(Map<String, dynamic> json) {
    // 消息体可能是顶层字段、data 包裹，或 data.pk_battle_info / pk_info 再包一层。
    Map<String, dynamic> data = _asMap(json['data']);
    for (final String key in const <String>['pk_battle_info', 'pk_info']) {
      final Map<String, dynamic> nested = _asMap(data[key]);
      if (nested.isNotEmpty) {
        data = nested;
        break;
      }
    }
    if (data.isEmpty) {
      data = json;
    }
    Object? pick(String key) => data[key] ?? json[key];
    return PkBattleInfo(
      pkId: pickInt(pick('pk_id')),
      status: pickInt(pick('pk_status')),
      uid: pickInt(pick('uid')),
      roomId: pickInt(pick('room_id')),
      uname: pick('uname') as String?,
      face: pick('face') as String?,
      endTime: pickInt(pick('end_time')),
    );
  }

  /// PK_INFO / pk/info 里的所有连线对象（本房间主播自己会被排除）。
  static List<PkBattleInfo> fromPkInfoList(
    Map<String, dynamic> json, {
    int? selfUid,
    int? selfRoomId,
  }) {
    final Object? rawData = json['data'];
    final Map<String, dynamic> data = rawData is Map
        ? _asMap(rawData)
        : json;
    final Object? rawMembers = data['members'] ?? json['members'];
    if (rawMembers is! List || rawMembers.isEmpty) {
      return const <PkBattleInfo>[];
    }
    final Map<String, dynamic> basic = _asMap(data['pk_basic']);
    final int? pkId = pickInt(basic['pk_id']);
    final int? endTime = pickInt(basic['end_time']);
    final int? status = pickInt(basic['status']);
    final List<PkBattleInfo> all = <PkBattleInfo>[];
    final List<PkBattleInfo> others = <PkBattleInfo>[];
    for (final Object? raw in rawMembers) {
      if (raw is! Map) continue;
      final Map<String, dynamic> member = _asMap(raw);
      final int? uid = pickInt(member['uid']);
      final int? roomId = pickInt(member['room_id']);
      if (uid == null && roomId == null) {
        continue;
      }
      final PkBattleInfo item = PkBattleInfo(
        pkId: pkId,
        status: status,
        endTime: endTime,
        uid: uid,
        roomId: roomId,
        uname: member['uname'] as String?,
        face: member['face'] as String?,
        votes: pickInt(member['votes']),
      );
      all.add(item);
      final bool isSelf = (selfUid != null && uid == selfUid) ||
          (selfRoomId != null && roomId == selfRoomId);
      if (!isSelf) {
        others.add(item);
      }
    }
    // 过滤后为空说明 members 里所有人 room_id 都等于本房间（多路连麦的常见形态），
    // 这时宁可全展示，也好过什么都不显示。
    return others.isEmpty ? all : others;
  }

  /// 第一个连线对象（兼容旧调用）。
  static PkBattleInfo? fromPkInfo(
    Map<String, dynamic> json, {
    int? selfUid,
    int? selfRoomId,
  }) {
    final List<PkBattleInfo> list = fromPkInfoList(
      json,
      selfUid: selfUid,
      selfRoomId: selfRoomId,
    );
    return list.isEmpty ? null : list.first;
  }
}

Map<String, dynamic> _asMap(Object? value) => switch (value) {
  final Map<String, dynamic> map => map,
  final Map<dynamic, dynamic> map => map.map(
    (key, value) => MapEntry(key.toString(), value),
  ),
  _ => const <String, dynamic>{},
};
