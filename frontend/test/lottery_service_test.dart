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
    expect(resultContainsTicketCode('KL123456', 'Winning number: KL654321'),
        isFalse);
  });

  test('parses saved draws and their winning numbers', () {
    final draw = LotteryDraw.fromJson({
      'id': 7,
      'lottery_name': 'KARUNYA PLUS',
      'draw_code': 'KN-643',
      'draw_date': '2026-09-28',
      'winners': [
        {
          'prize_tier': '1st',
          'prize_amount': 10000000,
          'winning_number': '123456'
        },
      ],
    });

    expect(draw.lotteryName, 'KARUNYA PLUS');
    expect(draw.drawCode, 'KN-643');
    expect(draw.drawDate, '2026-09-28');
    expect(draw.winners.single.prizeTier, '1st');
    expect(draw.winners.single.winningNumber, '123456');
    expect(draw.winners.single.prizeAmount, 10000000);
  });

  test('groups draw winners by prize tier while preserving amounts and order',
      () {
    final draw = LotteryDraw.fromJson({
      'id': 8,
      'lottery_name': 'THIRUVONAM BUMPER',
      'draw_date': '2026-09-26',
      'winners': [
        {
          'prize_tier': '1st',
          'prize_amount': 300000000,
          'winning_number': 'TL360615'
        },
        {
          'prize_tier': 'Consolation',
          'prize_amount': 500000,
          'winning_number': 'TA360615'
        },
        {
          'prize_tier': 'Consolation',
          'prize_amount': 500000,
          'winning_number': 'TB360615'
        },
        {'prize_tier': '6th', 'prize_amount': 5000, 'winning_number': '0178'},
      ],
    });

    final groups = draw.winnersByPrizeTier;

    expect(groups.keys.toList(), ['1st', 'Consolation', '6th']);
    expect(draw.firstPrize?.prizeAmount, 300000000);
    expect(
        groups['Consolation']!.map((winner) => winner.winningNumber).toList(), [
      'TA360615',
      'TB360615',
    ]);
    expect(groups['6th']!.single.prizeAmount, 5000);
  });

  test(
      'defaults to the published results feed when no runtime config is provided',
      () {
    final service = LotteryService();

    expect(service.usesPublishedResults, isTrue);
    expect(service.resultsJsonUrl, contains('raw.githubusercontent.com'));
    expect(service.baseUrl, isNot(contains('127.0.0.1')));
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
                {
                  'prize_tier': '1st',
                  'prize_amount': 10000000,
                  'winning_number': 'PH901174'
                },
              ],
            },
              {
                'id': 6,
                'lottery_name': 'KARUNYA PLUS',
                'draw_date': '2026-09-24',
                'winners': [
                  {
                    'prize_tier': '2nd',
                    'prize_amount': 3000000,
                    'winning_number': 'PH901174'
                  },
                ],
              },
          ]),
          200,
        );
      }),
    );

    final draws = await service.getResults();
    final matches = await service.checkTicket(
      'PH 901174',
      drawDate: '2026-10-01',
    );

    expect(service.usesPublishedResults, isTrue);
    expect(draws.first.lotteryName, 'KARUNYA PLUS');
    expect(draws, hasLength(2));
    expect(matches, hasLength(1));
    expect(matches.single.prizeTier, '1st');
    expect(matches.single.prizeAmount, 10000000);
  });

  test('sends the selected draw date when checking through the local API',
      () async {
    final service = LotteryService(
      baseUrl: 'https://api.example.com',
      resultsJsonUrl: '',
      client: MockClient((request) async {
        expect(request.url.path, '/check-ticket');
        expect(jsonDecode(request.body), {
          'ticket_code': 'PH 901174',
          'draw_date': '2026-10-01',
        });
        return http.Response(
          jsonEncode({
            'matches': [
              {
                'lottery_name': 'KARUNYA PLUS',
                'draw_date': '2026-10-01',
                'prize_tier': '1st',
                'prize_amount': 10000000,
                'winning_number': 'PH901174',
              },
            ],
          }),
          200,
        );
      }),
    );

    final matches = await service.checkTicket(
      'PH 901174',
      drawDate: '2026-10-01',
    );

    expect(matches.single.drawDate, '2026-10-01');
  });
}
