import 'package:PiliPlus/models_new/live/live_pk_battle/pk_battle_info.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PkBattleInfo', () {
    test('parses PRE message top level fields', () {
      final info = PkBattleInfo.fromJson(<String, dynamic>{
        'cmd': 'PK_BATTLE_PRE',
        'pk_status': 1,
        'pk_id': 123,
        'room_id': 5050,
        'uid': 42,
        'uname': '对手',
        'face': 'https://example.com/a.jpg',
      });
      expect(info.status, 1);
      expect(info.pkId, 123);
      expect(info.roomId, 5050);
      expect(info.uid, 42);
      expect(info.uname, '对手');
      expect(info.isEnded, isFalse);
    });

    test('parses nested data payload and string numbers', () {
      final info = PkBattleInfo.fromJson(<String, dynamic>{
        'cmd': 'PK_BATTLE_START',
        'data': <String, dynamic>{
          'room_id': '6001',
          'uname': 'nested',
          'pk_status': '2',
        },
      });
      expect(info.roomId, 6001);
      expect(info.status, 2);
      expect(info.uname, 'nested');
    });

    test('merge keeps previous identity when PROCESS has votes only', () {
      final first = PkBattleInfo.fromJson(<String, dynamic>{
        'room_id': 5050,
        'uname': '对手',
        'face': 'f',
        'pk_status': 2,
      });
      final process = PkBattleInfo.fromJson(<String, dynamic>{
        'cmd': 'PK_BATTLE_PROCESS',
        'votes': <dynamic>[],
      });
      final merged = process.merge(first);
      expect(merged.roomId, 5050);
      expect(merged.uname, '对手');
      expect(merged.face, 'f');
      expect(merged.status, 2);
    });

    test('end status marks finished', () {
      final info = PkBattleInfo.fromJson(<String, dynamic>{'pk_status': 5});
      expect(info.isEnded, isTrue);
    });

    test('parses data.pk_battle_info nesting used by *_NEW messages', () {
      final info = PkBattleInfo.fromJson(<String, dynamic>{
        'cmd': 'PK_BATTLE_START_NEW',
        'data': <String, dynamic>{
          'pk_battle_info': <String, dynamic>{
            'room_id': 7002,
            'uname': 'nested_battle',
            'pk_status': 2,
          },
        },
      });
      expect(info.roomId, 7002);
      expect(info.uname, 'nested_battle');
      expect(info.status, 2);
    });

    test('fromPkInfo picks the member that is not the local anchor', () {
      final info = PkBattleInfo.fromPkInfo(<String, dynamic>{
        'cmd': 'PK_INFO',
        'data': <String, dynamic>{
          'members': <dynamic>[
            <String, dynamic>{'uid': 111, 'uname': 'me', 'room_id': 5},
            <String, dynamic>{
              'uid': '222',
              'uname': 'rival',
              'room_id': '6001',
              'face': 'f',
            },
          ],
        },
      }, selfUid: 111);
      expect(info, isNotNull);
      expect(info!.uid, 222);
      expect(info.roomId, 6001);
      expect(info.uname, 'rival');
      expect(info.face, 'f');
    });

    test('fromPkInfo falls back to all members when only self matches', () {
      final info = PkBattleInfo.fromPkInfo(<String, dynamic>{
        'data': <String, dynamic>{
          'members': <dynamic>[
            <String, dynamic>{'uid': 111, 'room_id': 5},
          ],
        },
      }, selfUid: 111);
      expect(info, isNotNull);
      expect(info!.uid, 111);
    });
  });

  test('fromPkInfoList returns every connected member except self', () {
    final Map<String, dynamic> json = <String, dynamic>{
      'cmd': 'PK_INFO',
      'data': <String, dynamic>{
        'members': <dynamic>[
          <String, dynamic>{'uid': 1, 'uname': 'self', 'room_id': 100},
          <String, dynamic>{'uid': 2, 'uname': 'a', 'room_id': 200},
          <String, dynamic>{'uid': 3, 'uname': 'b', 'room_id': 300},
        ],
      },
    };
    final List<PkBattleInfo> list = PkBattleInfo.fromPkInfoList(
      json,
      selfUid: 1,
      selfRoomId: 100,
    );
    expect(list.length, 2);
    expect(list.map((PkBattleInfo e) => e.uname).toList(), <String>['a', 'b']);
  });
}