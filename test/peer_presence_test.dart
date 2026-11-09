import 'package:flutter_test/flutter_test.dart';
import 'package:mutual_transfer/models.dart';
import 'package:mutual_transfer/ui/components.dart';

void main() {
  test('last online labels distinguish recent, calendar and unknown times', () {
    final now = DateTime(2026, 11, 9, 14, 30);
    expect(formatLastSeen(null, now: now), '暂无记录');
    expect(formatLastSeen(now, now: now), '刚刚');
    expect(
      formatLastSeen(now.subtract(const Duration(minutes: 5)), now: now),
      '5 分钟前',
    );
    expect(formatLastSeen(DateTime(2026, 11, 9, 10, 5), now: now), '今天 10:05');
    expect(formatLastSeen(DateTime(2026, 11, 8, 18, 5), now: now), '昨天 18:05');
    expect(
      formatLastSeen(DateTime(2026, 10, 1, 8, 5), now: now),
      '10-01 08:05',
    );
    expect(
      formatLastSeen(DateTime(2025, 12, 31, 23, 59), now: now),
      '2025-12-31 23:59',
    );
    final observed = DateTime(2026, 11, 9, 10, 5, 7);
    expect(
      formatLastSeen(observed.toUtc(), now: now, precise: true),
      '2026-11-09 10:05:07',
    );
    expect(
      formatLastSeen(now.add(const Duration(minutes: 5)), now: now),
      '今天 14:35',
    );
    expect(
      formatLastSeen(DateTime(2025, 12, 31, 23), now: DateTime(2026, 1, 1, 8)),
      '昨天 23:00',
    );
  });

  test('an offline placeholder has no invented observation time', () {
    final peer = Peer(
      id: 'unseen',
      name: '群成员',
      host: '192.168.1.2',
      port: 45878,
      online: false,
    );
    expect(peer.lastSeen, isNull);
  });
}
