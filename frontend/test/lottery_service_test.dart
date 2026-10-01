import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kerala_lottery_app/lottery_service.dart';

void main() {
  test('matches a ticket code despite spaces and punctuation', () {
    expect(resultContainsTicketCode('KL-123 456', 'Prize: KL 123456'), isTrue);
  });

  test('does not match short values', () {
    expect(resultContainsTicketCode('123', 'Winning number: 123'), isFalse);
  });

  test('reports no match when the code is absent', () {
    expect(resultContainsTicketCode('KL123456', 'Winning number: KL654321'), isFalse);
  });

  test('parses saved draws and their winning numbers', () {
    final draw = LotteryDraw.fromJson({
      'id': 7,
      'lottery_name': 'KARUNYA PLUS',
      'draw_date': '2026-09-28',
      'winners': [
        {'prize_tier': '1st', 'winning_number': '123456'},
      ],
    });

    expect(draw.lotteryName, 'KARUNYA PLUS');
    expect(draw.drawDate, '2026-09-28');
    expect(draw.winners.single.prizeTier, '1st');
    expect(draw.winners.single.winningNumber, '123456');
  });

  test('loads published results and checks tickets without the API', () async {
    final service = LotteryService(
      resultsJsonUrl: 'https://example.com/results.json',
      client: MockClient((request) async {
        expect(request.url.toString(), 'https://example.com/results.json');
        return http.Response(
          jsonEncode([
            {
              'id': 7,
              'lottery_name': 'KARUNYA PLUS',
              'draw_date': '2026-10-01',
              'winners': [
                {'prize_tier': '1st', 'winning_number': 'PH901174'},
              ],
            },
          ]),
          200,
        );
      }),
    );

    final draws = await service.getResults();
    final matches = await service.checkTicket('PH 901174');

    expect(service.usesPublishedResults, isTrue);
    expect(draws.single.lotteryName, 'KARUNYA PLUS');
    expect(matches.single.prizeTier, '1st');
  });
}