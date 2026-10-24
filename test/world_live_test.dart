import 'dart:io';

import 'package:artha/modules/finance/insights/world.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reads the real sources. Run with ARTHA_LIVE=1.
void main() {
  final live = Platform.environment['ARTHA_LIVE'] == '1';

  test('the real sources still parse', () async {
    final data = await WorldService().refresh(DateTime.now().toUtc().toIso8601String().substring(0, 10));
    // ignore: avoid_print
    print('${data.market.toJson()} failed=${data.failed} news=${data.news.length}');
    final day = DateTime.now().toUtc().toIso8601String().substring(0, 10);
    final ranked = rankNews(
      data.news,
      newsInterests(saves: true, invests: true, mortgage: false, borrows: false, pension: true),
      day,
    );
    for (final n in ranked) {
      // ignore: avoid_print
      print('${n.date} ${n.source}: ${n.title} ${n.topics}');
    }
    expect(data.market.bankRate, isNotNull);
    expect(data.market.cpi, isNotNull);
    expect(data.failed, isEmpty);
    expect(data.news, isNotEmpty);
  }, skip: live ? false : 'set ARTHA_LIVE=1');
}
