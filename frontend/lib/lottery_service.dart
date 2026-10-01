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
    required this.winningNumber,
  });

  final String lotteryName;
  final String drawDate;
  final String prizeTier;
  final String winningNumber;

  factory LotteryTicketMatch.fromJson(Map<String, dynamic> json) {
    return LotteryTicketMatch(
      lotteryName: json['lottery_name'] as String? ?? 'Unknown',
      drawDate: json['draw_date'] as String? ?? '',
      prizeTier: json['prize_tier'] as String? ?? 'Unknown',
      winningNumber: json['winning_number'] as String? ?? '',
    );
  }
}

class LotteryPrizeWinner {
  const LotteryPrizeWinner({required this.prizeTier, required this.winningNumber});

  final String prizeTier;
  final String winningNumber;

  factory LotteryPrizeWinner.fromJson(Map<String, dynamic> json) {
    return LotteryPrizeWinner(
      prizeTier: json['prize_tier'] as String? ?? 'Unknown',
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

class LotteryService {
  LotteryService({String? baseUrl, String? resultsJsonUrl, http.Client? client})
      : _client = client ?? http.Client(),
        baseUrl = (baseUrl ?? const String.fromEnvironment(
          'API_BASE_URL',
          defaultValue: 'http://127.0.0.1:8000',
        )).replaceAll(RegExp(r'/$'), ''),
        resultsJsonUrl = (resultsJsonUrl ?? const String.fromEnvironment('RESULTS_JSON_URL')).trim();

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
      if (normalizedCode.isEmpty) {
        throw Exception('Enter a ticket number.');
      }

      final draws = await getResults();
      return [
        for (final draw in draws)
          for (final winner in draw.winners)
            if (winner.winningNumber.contains(normalizedCode))
              LotteryTicketMatch(
                lotteryName: draw.lotteryName,
                drawDate: draw.drawDate,
                prizeTier: winner.prizeTier,
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
}
