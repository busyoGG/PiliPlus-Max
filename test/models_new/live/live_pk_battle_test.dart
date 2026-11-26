import 'package:PiliPlus/models_new/live/live_pk_battle/pk_battle_info.dart';
import 'package:flutter_test/flutter_test.dart';

/// 真实采集的官方 /xlive/general-interface/v2/pk/info 响应（8 人连麦，字段精简）。
Map<String, dynamic> _payload() => <String, dynamic>{
  'pk_basic': <String, dynamic>{
    'pk_id': 402539093,
    'init_id': 21593109,
    'init_uid': 73415842,
    'status': 201,
    'start_time': 1795678075,
    'end_time': 1795681675,
    'template_id': 'multi_conn_grid',
  },
  'members': <dynamic>[
    <String, dynamic>{
      'uid': 318386480,
      'uname': 'a',
      'room_id': 24967529,
      'votes': 2,
    },
    <String, dynamic>{
      'uid': 73415842,
      'uname': 'b',
      'room_id': 21593109,
      'votes': 507,
    },
    <String, dynamic>{
      'uid': 3706942363011152,
      'uname': 'c',
      'room_id': 1819686881,
      'votes': 4230,
    },
    <String, dynamic>{
      'uid': 3493290001304295,
      'uname': 'd',
      'room_id': 27732004,
      'votes': 4731,
    },
  ],
  'audience_open': false,
};

void main() {
  group('PkBattleInfo.fromJson', () {
    test('reads top-level fields', () {
      final info = PkBattleInfo.fromJson(<String, dynamic>{
        'pk_id': 1,
        'pk_status': 2,
        'uid': 3,
        'room_id': 4,
        'uname': 'u',
      });
      expect(info.pkId, 1);
      expect(info.status, 2);
      expect(info.uid, 3);
      expect(info.roomId, 4);
      expect(info.uname, 'u');
    });

    test('reads data wrapper', () {
      final info = PkBattleInfo.fromJson(<String, dynamic>{
        'cmd': 'PK_BATTLE_START',
        'data': <String, dynamic>{'room_id': '42', 'uname': 'x'},
      });
      expect(info.roomId, 42);
      expect(info.uname, 'x');
    });

    test('reads nested data.pk_battle_info', () {
      final info = PkBattleInfo.fromJson(<String, dynamic>{
        'data': <String, dynamic>{
          'pk_battle_info': <String, dynamic>{'pk_id': 9, 'room_id': 10},
        },
      });
      expect(info.pkId, 9);
      expect(info.roomId, 10);
    });
  });

  group('PkBattleInfo.merge', () {
    test('keeps identity when the next message only carries votes', () {
      const first = PkBattleInfo(uid: 1, roomId: 2, uname: 'a');
      final next = PkBattleInfo.fromJson(<String, dynamic>{
        'pk_status': 3,
      }).merge(first);
      expect(next.roomId, 2);
      expect(next.uname, 'a');
      expect(next.status, 3);
    });
  });

  group('PkBattleInfo.isEnded', () {
    test('uses end_time instead of the raw status code', () {
      final past =
          DateTime.now().millisecondsSinceEpoch ~/ 1000 - 60;
      final future =
          DateTime.now().millisecondsSinceEpoch ~/ 1000 + 600;
      expect(PkBattleInfo(endTime: past).isEnded, isTrue);
      expect(PkBattleInfo(endTime: future).isEnded, isFalse);
      // 官方 201/601 都属于进行中，不能被当成结束。
      expect(PkBattleInfo(status: 601, endTime: future).isEnded, isFalse);
      expect(const PkBattleInfo().isEnded, isFalse);
    });
  });

  group('PkBattleInfo.fromPkInfoList', () {
    test('excludes the room owner and keeps every other connection', () {
      final items = PkBattleInfo.fromPkInfoList(
        <String, dynamic>{'cmd': 'PK_INFO', 'data': _payload()},
        selfUid: 73415842,
        selfRoomId: 21593109,
      );
      expect(items.map((e) => e.uname), <String>['a', 'c', 'd']);
    });

    test('carries pk_basic and votes over to each member', () {
      final items = PkBattleInfo.fromPkInfoList(<String, dynamic>{
        'data': _payload(),
      });
      expect(items, hasLength(4));
      expect(items.first.pkId, 402539093);
      expect(items.first.endTime, 1795681675);
      expect(items.first.votes, 2);
    });

    test('falls back to every member when only self matches', () {
      final items = PkBattleInfo.fromPkInfoList(<String, dynamic>{
        'data': <String, dynamic>{
          'members': <dynamic>[
            <String, dynamic>{'uid': 111, 'uname': 'a', 'room_id': 9},
          ],
        },
      }, selfUid: 111, selfRoomId: 9);
      expect(items, hasLength(1));
      expect(items.first.uid, 111);
    });

    test('returns empty without members', () {
      expect(
        PkBattleInfo.fromPkInfoList(<String, dynamic>{'cmd': 'PK_INFO'}),
        isEmpty,
      );
    });

    test('fromPkInfo keeps working as a single-item wrapper', () {
      final info = PkBattleInfo.fromPkInfo(<String, dynamic>{
        'data': _payload(),
      }, selfUid: 73415842, selfRoomId: 21593109);
      expect(info?.uname, 'a');
    });
  });
}
