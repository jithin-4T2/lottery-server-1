import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;

bool resultContainsTicketCode(String ticketCode, String resultText) {
  final normalizedCode = ticketCode.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  final normalizedResults = resultText.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  return normalizedCode.length >= 6 && normalizedResults.contains(normalizedCode);
}

class LotteryTicketMatch {
  const LotteryTicketMatch({
    required this.lotteryName,
    required this.drawDate,
    required this.prizeTier,
    required this.prizeAmount,
    required this.winningNumber,
  });

  final String lotteryName;
  final String drawDate;
  final String prizeTier;
  final int? prizeAmount;
  final String winningNumber;

  factory LotteryTicketMatch.fromJson(Map<String, dynamic> json) {
    return LotteryTicketMatch(
      lotteryName: json['lottery_name'] as String? ?? 'Unknown',
      drawDate: json['draw_date'] as String? ?? '',
      prizeTier: json['prize_tier'] as String? ?? 'Unknown',
      prizeAmount: (json['prize_amount'] as num?)?.toInt(),
      winningNumber: json['winning_number'] as String? ?? '',
    );
  }
}

class LotteryPrizeWinner {
  const LotteryPrizeWinner({
    required this.prizeTier,
    required this.prizeAmount,
    required this.winningNumber,
  });

  final String prizeTier;
  final int? prizeAmount;
  final String winningNumber;

  factory LotteryPrizeWinner.fromJson(Map<String, dynamic> json) {
    return LotteryPrizeWinner(
      prizeTier: json['prize_tier'] as String? ?? 'Unknown',
      prizeAmount: (json['prize_amount'] as num?)?.toInt(),
      winningNumber: json['winning_number'] as String? ?? '',
    );
  }
}

class LotteryDraw {
  const LotteryDraw({
    required this.id,
    required this.lotteryName,
    required this.drawDate,
    required this.winners,
  });

  final int id;
  final String lotteryName;
  final String drawDate;
  final List<LotteryPrizeWinner> winners;

  factory LotteryDraw.fromJson(Map<String, dynamic> json) {
    return LotteryDraw(
      id: (json['id'] as num?)?.toInt() ?? 0,
      lotteryName: json['lottery_name'] as String? ?? 'Unknown lottery',
      drawDate: json['draw_date'] as String? ?? '',
      winners: (json['winners'] as List<dynamic>? ?? const [])
          .map((winner) => LotteryPrizeWinner.fromJson(winner as Map<String, dynamic>))
          .toList(),
    );
  }
}

const _defaultPublishedResultsUrl =
    'https://raw.githubusercontent.com/jithin-4T2/lottery-server-1/main/frontend/web/results.json';

class LotteryService {
  LotteryService({String? baseUrl, String? resultsJsonUrl, http.Client? client})
      : _client = client ?? http.Client(),
        baseUrl = _normalizeUrl(
          baseUrl ?? const String.fromEnvironment('API_BASE_URL', defaultValue: ''),
        ),
        resultsJsonUrl = _resolveResultsJsonUrl(
          resultsJsonUrl,
          baseUrl ?? const String.fromEnvironment('API_BASE_URL', defaultValue: ''),
        );

  static String _normalizeUrl(String value) => value.trim().replaceAll(RegExp(r'/$'), '');

  static String _resolveResultsJsonUrl(String? resultsJsonUrl, String? baseUrl) {
    final explicitResults = (resultsJsonUrl ?? const String.fromEnvironment('RESULTS_JSON_URL', defaultValue: '')).trim();
    final explicitBaseUrl = (baseUrl ?? const String.fromEnvironment('API_BASE_URL', defaultValue: '')).trim();

    if (explicitResults.isNotEmpty) {
      return explicitResults;
    }

    if (explicitBaseUrl.isEmpty) {
      return _defaultPublishedResultsUrl;
    }

    return '';
  }

  final http.Client _client;
  final String baseUrl;
  final String resultsJsonUrl;

  bool get usesPublishedResults => resultsJsonUrl.isNotEmpty;

  Future<List<LotteryDraw>> getResults() async {
    final uri = usesPublishedResults ? Uri.parse(resultsJsonUrl) : Uri.parse('$baseUrl/results');
    final response = await _client.get(uri).timeout(
          const Duration(seconds: 20),
        );
    if (response.statusCode != 200) {
      throw Exception('The server could not load saved results.');
    }

    final draws = jsonDecode(response.body) as List<dynamic>;
    return draws
        .map((draw) => LotteryDraw.fromJson(draw as Map<String, dynamic>))
        .toList();
  }

  Future<void> fetchLatestResult() async {
    if (usesPublishedResults) return;

    final response = await _client.post(Uri.parse('$baseUrl/results/fetch-latest')).timeout(
          const Duration(seconds: 120),
        );
    if (response.statusCode != 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(body['detail'] ?? 'The latest result could not be fetched.');
    }
  }

  Future<String> parsePdf(PlatformFile pdf) async {
    final bytes = pdf.bytes;
    if (bytes == null) {
      throw const FormatException('Could not read the selected PDF.');
    }

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/parse'),
    )..files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: pdf.name,
        ),
      );

    final streamedResponse = await request.send().timeout(
      const Duration(seconds: 90),
    );
    final response = await http.Response.fromStream(streamedResponse);
    final body = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode != 200) {
      throw Exception(body['detail'] ?? 'The server could not process this PDF.');
    }

    return const JsonEncoder.withIndent('  ').convert(body);
  }

  Future<List<LotteryTicketMatch>> checkTicket(String ticketCode) async {
    if (usesPublishedResults) {
      final normalizedCode = ticketCode.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
      if (normalizedCode.length < 4) {
        throw Exception('Enter at least the last four digits of your ticket.');
      }

      final draws = await getResults();
      return [
        for (final draw in draws)
          for (final winner in draw.winners)
            if (_ticketMatchesNumber(normalizedCode, winner.winningNumber))
              LotteryTicketMatch(
                lotteryName: draw.lotteryName,
                drawDate: draw.drawDate,
                prizeTier: winner.prizeTier,
                prizeAmount: winner.prizeAmount,
                winningNumber: winner.winningNumber,
              ),
      ];
    }

    final response = await _client.post(
      Uri.parse('$baseUrl/check-ticket'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'ticket_code': ticketCode}),
    ).timeout(const Duration(seconds: 30));

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200) {
      throw Exception(body['detail'] ?? 'Could not check the ticket.');
    }

    final matches = (body['matches'] as List<dynamic>? ?? const [])
        .map((entry) => LotteryTicketMatch.fromJson(entry as Map<String, dynamic>))
        .toList();
    return matches;
  }

  static bool _ticketMatchesNumber(String ticketCode, String winningNumber) {
    if (winningNumber == ticketCode) return true;
    if (winningNumber.length == 8 && winningNumber.endsWith(ticketCode)) return true;
    return winningNumber.length == 4 && ticketCode.endsWith(winningNumber);
  }
}
