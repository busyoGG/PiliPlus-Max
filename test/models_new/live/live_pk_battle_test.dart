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
  });
}