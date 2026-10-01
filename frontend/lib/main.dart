import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'lottery_service.dart';

void main() {
  runApp(const KeralaLotteryApp());
}

const _brandBlue = Color(0xFF1553A6);
const _deepBlue = Color(0xFF10458F);
const _pageBackground = Color(0xFFF1F3F6);
const _cardWhite = Color(0xFFFFFFFF);
const _mintDeep = Color(0xFF1D7D76);
const _textDark = Color(0xFF1E2C3A);
const _mutedText = Color(0xFF7A8594);
const _successGreen = Color(0xFF2E9D70);

class KeralaLotteryApp extends StatelessWidget {
  const KeralaLotteryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kerala Lottery Checker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: _pageBackground,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _brandBlue,
          primary: _brandBlue,
          surface: _pageBackground,
        ),
        fontFamily: 'Roboto',
      ),
      home: const LotteryHomePage(),
    );
  }
}

class LotteryHomePage extends StatefulWidget {
  const LotteryHomePage({super.key});

  @override
  State<LotteryHomePage> createState() => _LotteryHomePageState();
}

class _LotteryHomePageState extends State<LotteryHomePage> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _ticketController = TextEditingController();
  final _lotteryService = LotteryService();
  List<LotteryDraw> _savedDraws = [];
  int _selectedTab = 0;
  String _searchQuery = '';
  String? _selectedDraw;
  DateTime? _selectedDrawDate;
  String? _statusMessage;
  bool _isCheckingTicket = false;
  bool _isLoadingSavedDraws = true;
  bool _isFetchingLatest = false;
  String? _savedResultsError;
  List<LotteryTicketMatch>? _ticketMatches;

  @override
  void initState() {
    super.initState();
    _loadSavedDraws();
  }

  @override
  void dispose() {
    _ticketController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedDraws() async {
    try {
      final draws = await _lotteryService.getResults();
      if (!mounted) return;
      setState(() {
        _savedDraws = draws;
        _savedResultsError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _savedResultsError =
          error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoadingSavedDraws = false);
    }
  }

  Future<void> _fetchLatestDraw() async {
    if (_isFetchingLatest) return;
    setState(() {
      _isFetchingLatest = true;
      _savedResultsError = null;
    });
    try {
      await _lotteryService.fetchLatestResult();
      final draws = await _lotteryService.getResults();
      if (!mounted) return;
      setState(() {
        _savedDraws = draws;
        _savedResultsError = draws.isEmpty
            ? 'No published lottery results are available yet.'
            : null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _savedResultsError =
          error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isFetchingLatest = false);
    }
  }

  Future<void> _scanTicket() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const BarcodeScannerPage()),
    );
    if (code != null && mounted) {
      _ticketController.text = code;
      await _checkTicket();
    }
  }

  Future<void> _selectDrawDate() async {
    final today = DateTime.now();
    final selectedDate = await showDatePicker(
      context: context,
      initialDate: _selectedDrawDate ?? today,
      firstDate: DateTime(2000),
      lastDate: DateTime(today.year, today.month, today.day),
    );
    if (selectedDate == null || !mounted) return;

    setState(() {
      _selectedDrawDate = selectedDate;
      _ticketMatches = null;
      _statusMessage = null;
    });
  }

  Future<void> _checkTicket() async {
    final code = _ticketController.text.trim();
    if (_isCheckingTicket) return;
    if (code.isEmpty || _selectedDrawDate == null) {
      setState(() {
        _ticketMatches = null;
        _statusMessage =
            code.isEmpty
                ? 'Enter a ticket number to check.'
                : 'Select the draw date to check this ticket.';
      });
      return;
    }

    setState(() {
      _isCheckingTicket = true;
      _ticketMatches = null;
      _statusMessage = null;
    });
    try {
      final matches = await _lotteryService.checkTicket(
        code,
        drawDate: _isoDrawDate(_selectedDrawDate!),
      );
      if (mounted) setState(() => _ticketMatches = matches);
    } catch (error) {
      if (mounted) {
        setState(() =>
            _statusMessage = error.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _isCheckingTicket = false);
    }
  }

  String _isoDrawDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  String _displayDrawDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/'
      '${date.year.toString().padLeft(4, '0')}';

  void _showDrawResults(LotteryDraw draw) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => LotteryResultPage(draw: draw),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        toolbarHeight: 52,
        backgroundColor: _brandBlue,
        foregroundColor: Colors.white,
        titleSpacing: 2,
        leading: IconButton(
          tooltip: 'Open navigation menu',
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
          icon: const Icon(Icons.menu, size: 20),
        ),
        title: const Text(
          'Ponkudam',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            tooltip: 'Open ticket scanner',
            onPressed: () => setState(() => _selectedTab = 1),
            icon: const Icon(Icons.qr_code_scanner, size: 21),
          ),
        ],
      ),
      drawer: _buildDrawer(),
      body: IndexedStack(
        index: _selectedTab,
        children: [
          _buildHomePage(),
          _buildCheckerPage(),
          _buildPredictionPage(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedTab,
        onTap: (index) => setState(() => _selectedTab = index),
        type: BottomNavigationBarType.fixed,
        backgroundColor: _brandBlue,
        selectedItemColor: Colors.white,
        unselectedItemColor: const Color(0xFFB7CBE7),
        selectedFontSize: 10,
        unselectedFontSize: 9,
        iconSize: 19,
        elevation: 8,
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home),
              label: 'Home'),
          BottomNavigationBarItem(
              icon: Icon(Icons.qr_code_scanner), label: 'Scan'),
          BottomNavigationBarItem(
              icon: Icon(Icons.insights_outlined), label: 'Prediction'),
        ],
      ),
    );
  }

  Widget _buildHomePage() {
    final recentDraws = _savedDraws.take(3).toList();
    final filteredDraws = _savedDraws
        .where((draw) =>
            draw.lotteryName.contains(_searchQuery.trim().toUpperCase()))
        .toList();

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _cardWhite,
                borderRadius: BorderRadius.circular(22),
                boxShadow: const [
                  BoxShadow(
                    color: Color.fromRGBO(0, 0, 0, 0.04),
                    blurRadius: 16,
                    offset: Offset(0, 5),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: const BoxDecoration(
                          color: Color(0xFF37B6A1),
                          borderRadius: BorderRadius.all(Radius.circular(12)),
                        ),
                        child: const Icon(Icons.qr_code,
                            color: Colors.white, size: 20),
                      ),
                      const SizedBox(width: 12),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'BHAGYAM SCAN',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: _textDark,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Kerala Lottery Results',
                            style: TextStyle(
                              fontSize: 12,
                              color: _mutedText,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Good evening, Jithin',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: _textDark,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Scan your lottery ticket and check if you\'re a winner!',
                    style: TextStyle(
                      fontSize: 14,
                      color: _mutedText,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  InkWell(
                    onTap: () => setState(() => _selectedTab = 1),
                    borderRadius: const BorderRadius.all(Radius.circular(16)),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          vertical: 18, horizontal: 18),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF2AAEA3), Color(0xFF1E8E85)],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                        borderRadius: BorderRadius.all(Radius.circular(16)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 54,
                            height: 54,
                            decoration: const BoxDecoration(
                              color: Color.fromRGBO(255, 255, 255, 0.18),
                              borderRadius:
                                  BorderRadius.all(Radius.circular(16)),
                            ),
                            child: const Icon(Icons.qr_code_scanner,
                                color: Colors.white, size: 28),
                          ),
                          const SizedBox(width: 14),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Scan Ticket',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Scan barcode to check your lottery result',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.arrow_forward_ios_rounded,
                              color: Colors.white, size: 18),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_ticketMatches != null) ...[
              const SizedBox(height: 18),
              _buildLastTicketCheckCard(),
            ],
            const SizedBox(height: 22),
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Recent Results',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: _textDark,
                  ),
                ),
                Text(
                  'Latest draws',
                  style: TextStyle(
                    fontSize: 12,
                    color: _brandBlue,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_isLoadingSavedDraws)
              const Center(child: CircularProgressIndicator())
            else if (recentDraws.isEmpty)
              _buildEmptyResults()
            else
              Column(
                children: recentDraws.map((draw) {
                  final firstPrizeAmount = draw.firstPrize?.prizeAmount;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: const BorderRadius.all(Radius.circular(14)),
                      border: Border.all(color: const Color(0xFFE8EDF2)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: const BoxDecoration(
                            color: Color(0xFFEAF4F2),
                            borderRadius: BorderRadius.all(Radius.circular(10)),
                          ),
                          child: Center(
                            child: Text(
                              draw.lotteryName.substring(0, 1).toUpperCase(),
                              style: const TextStyle(
                                color: _mintDeep,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                draw.lotteryName,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: _textDark,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${draw.drawCode ?? 'Draw code unavailable'} · ${draw.drawDate}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: _mutedText,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              firstPrizeAmount == null
                                  ? '1st prize unavailable'
                                  : _formatRupees(firstPrizeAmount),
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: _mintDeep,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              '1st prize · View result',
                              style: TextStyle(fontSize: 10, color: _mutedText),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            const SizedBox(height: 22),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'All Lottery Results',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: _textDark,
                  ),
                ),
                Text(
                  '${filteredDraws.length} draws',
                  style: const TextStyle(fontSize: 12, color: _mutedText),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              onChanged: (value) => setState(() => _searchQuery = value),
              decoration: InputDecoration(
                hintText: 'Search lottery draws',
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (_isLoadingSavedDraws)
              const Center(child: CircularProgressIndicator())
            else if (filteredDraws.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('No matching lottery results')),
              )
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: filteredDraws.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  mainAxisExtent: 112,
                ),
                itemBuilder: (context, index) =>
                    _drawTile(filteredDraws[index], index),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLastTicketCheckCard() {
    final matches = _ticketMatches!;
    final isWinner = matches.isNotEmpty;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isWinner ? const Color(0xFFE7F6EF) : const Color(0xFFF1F4F7),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isWinner ? const Color(0xFFB9E6D2) : const Color(0xFFDCE3E9),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isWinner ? 'You won!' : 'No win, better luck next time.',
            style: TextStyle(
              color: isWinner ? _successGreen : _textDark,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          if (isWinner)
            ...matches.map(
              (match) => Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${match.prizeTier} · ${match.lotteryName}',
                        style: const TextStyle(color: _textDark, fontSize: 12),
                      ),
                    ),
                    Text(
                      match.prizeAmount == null
                          ? 'Amount unavailable'
                          : _formatRupees(match.prizeAmount!),
                      style: const TextStyle(
                        color: _mintDeep,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Text(
              _ticketController.text.trim(),
              style: const TextStyle(color: _mutedText, fontSize: 12),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyResults() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _savedResultsError == null
                  ? Icons.inbox_outlined
                  : Icons.cloud_off_outlined,
              size: 38,
              color: const Color(0xFF78818D),
            ),
            const SizedBox(height: 10),
            Text(
              _savedResultsError == null
                  ? 'No saved results yet'
                  : 'Could not load results',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              _savedResultsError ??
                  (_lotteryService.usesPublishedResults
                      ? 'No published draws are available yet.'
                      : 'Fetch the latest official draw to add results to the server.'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Color(0xFF78818D)),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _isFetchingLatest ? null : _fetchLatestDraw,
              icon: _isFetchingLatest
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(_lotteryService.usesPublishedResults
                      ? Icons.sync
                      : Icons.download_outlined),
              label: Text(
                _isFetchingLatest
                    ? (_lotteryService.usesPublishedResults
                        ? 'Refreshing...'
                        : 'Fetching...')
                    : (_lotteryService.usesPublishedResults
                        ? 'Refresh results'
                        : 'Fetch latest result'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _drawTile(LotteryDraw draw, int index) {
    final firstPrizeAmount = draw.firstPrize?.prizeAmount;
    final isLatest = _savedDraws.isNotEmpty &&
        draw.id == _savedDraws.first.id;
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Color(0xFFE2E8EE)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showDrawResults(draw),
        child: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  const Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF2AAEA3), Color(0xFF1E8E85)],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 90),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(48),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        draw.drawCode ?? 'Code unavailable',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  if (isLatest)
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFD8423A),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'NEW',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 24, 8, 5),
                    child: Center(
                      child: Text(
                        draw.lotteryName,
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          height: 1.15,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Container(height: 1, color: const Color(0xFFF0F2F5)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      draw.drawDate,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _textDark,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      firstPrizeAmount == null
                          ? '1st prize N/A'
                          : _formatRupees(firstPrizeAmount),
                      maxLines: 1,
                      textAlign: TextAlign.right,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _mintDeep,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCheckerPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'CHECK YOUR TICKET',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: _deepBlue,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _selectedDraw ?? 'Scan a barcode or enter your ticket number',
            style: const TextStyle(fontSize: 15, color: Color(0xFF4D5B6B)),
          ),
          const SizedBox(height: 16),
          const Text(
            'DRAW DATE',
            style: TextStyle(
              color: _deepBlue,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 7),
          InkWell(
            onTap: _selectDrawDate,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFD8DEE7)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_month_outlined,
                      color: _brandBlue, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _selectedDrawDate == null
                          ? 'Select draw date'
                          : _displayDrawDate(_selectedDrawDate!),
                      style: TextStyle(
                        color: _selectedDrawDate == null
                            ? _mutedText
                            : _textDark,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Icon(Icons.edit_calendar_outlined,
                      color: _mutedText, size: 18),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _scanTicket,
              icon: const Icon(Icons.qr_code_scanner, size: 20),
              label: const Text('Scan ticket barcode'),
              style: FilledButton.styleFrom(
                backgroundColor: _brandBlue,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6)),
                textStyle:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: Text(
                'OR ENTER THE TICKET NUMBER',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  color: Color(0xFF78818D),
                ),
              ),
            ),
          ),
          TextField(
            controller: _ticketController,
            onChanged: (_) => setState(() {
              _ticketMatches = null;
              _statusMessage = null;
            }),
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              hintText: 'Enter ticket number',
              prefixIcon:
                  const Icon(Icons.confirmation_number_outlined, size: 20),
              isDense: true,
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: Color(0xFFD8DEE7)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: Color(0xFFD8DEE7)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _isCheckingTicket ? null : _checkTicket,
              icon: _isCheckingTicket
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.search),
              label: Text(
                  _isCheckingTicket ? 'Checking ticket...' : 'Check ticket'),
              style: FilledButton.styleFrom(
                backgroundColor: _mintDeep,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          ),
          if (_statusMessage != null) ...[
            const SizedBox(height: 12),
            _notice(_statusMessage!, isError: true),
          ],
          if (_ticketMatches != null) ...[
            const SizedBox(height: 12),
            if (_ticketMatches!.isEmpty)
              _notice('No win, better luck next time.', isError: true)
            else
              ..._ticketMatches!.map(_winningTicketCard),
          ],
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: const Color(0xFFE6ECF4),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 17, color: Color(0xFF52647A)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Choose the ticket draw date before checking. Confirm prize claims with the official Kerala State Lotteries publication.',
                    style: TextStyle(
                        fontSize: 11, height: 1.4, color: Color(0xFF52647A)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _winningTicketCard(LotteryTicketMatch match) {
    final prizeAmount = match.prizeAmount;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFE7F6EF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFB9E6D2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'You won!',
            style: TextStyle(
              color: _successGreen,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            prizeAmount == null
                ? '${match.prizeTier} · prize amount not in published data'
                : '${_formatRupees(prizeAmount)} · ${match.prizeTier}',
            style: const TextStyle(
              color: _mintDeep,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${match.lotteryName} · ${match.drawDate}',
            style: const TextStyle(color: _mutedText, fontSize: 12),
          ),
        ],
      ),
    );
  }

  String _formatRupees(int amount) {
    final digits = amount.toString();
    if (digits.length <= 3) return '₹$digits';

    var prefix = digits.substring(0, digits.length - 3);
    var grouped = digits.substring(digits.length - 3);
    while (prefix.length > 2) {
      grouped = '${prefix.substring(prefix.length - 2)},$grouped';
      prefix = prefix.substring(0, prefix.length - 2);
    }
    return '₹$prefix,$grouped';
  }

  Widget _buildPredictionPage() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.insights_outlined, size: 42, color: _brandBlue),
            const SizedBox(height: 12),
            const Text(
              'Predictions are not available',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF26364B)),
            ),
            const SizedBox(height: 7),
            const Text(
              'Lottery draws are random. Use official results to check your ticket.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13, height: 1.4, color: Color(0xFF78818D)),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => setState(() => _selectedTab = 1),
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Check a ticket'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawer() {
    return NavigationDrawer(
      selectedIndex: _selectedTab,
      onDestinationSelected: (index) {
        Navigator.of(context).pop();
        setState(() => _selectedTab = index);
      },
      children: const [
        Padding(
          padding: EdgeInsets.fromLTRB(28, 18, 16, 12),
          child: Text('Ponkudam',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        ),
        NavigationDrawerDestination(
            icon: Icon(Icons.home_outlined), label: Text('Home')),
        NavigationDrawerDestination(
            icon: Icon(Icons.qr_code_scanner), label: Text('Scan')),
        NavigationDrawerDestination(
            icon: Icon(Icons.insights_outlined), label: Text('Prediction')),
      ],
    );
  }

  Widget _notice(String message, {required bool isError}) {
    final color = isError ? const Color(0xFF9D4938) : const Color(0xFF286342);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isError ? const Color(0xFFFBECE8) : const Color(0xFFE8F3E9),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(isError ? Icons.search_off : Icons.check_circle_outline,
              color: color, size: 19),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                  fontSize: 12,
                  height: 1.35,
                  color: color,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class LotteryResultPage extends StatelessWidget {
  const LotteryResultPage({super.key, required this.draw});

  final LotteryDraw draw;

  @override
  Widget build(BuildContext context) {
    final prizeGroups = draw.winnersByPrizeTier.entries.toList();
    return Scaffold(
      backgroundColor: _pageBackground,
      appBar: AppBar(
        backgroundColor: _brandBlue,
        foregroundColor: Colors.white,
        title: Text(
          draw.lotteryName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(38),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
            child: Row(
              children: [
                const Icon(Icons.calendar_today_outlined,
                    size: 15, color: Colors.white70),
                const SizedBox(width: 7),
                Text(draw.drawDate,
                    style: const TextStyle(color: Colors.white, fontSize: 13)),
                const Spacer(),
                const Icon(Icons.confirmation_number_outlined,
                    size: 16, color: Colors.white70),
                const SizedBox(width: 6),
                Text(
                  '${draw.winners.length} numbers',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
      body: draw.winners.isEmpty
          ? const Center(child: Text('No winning numbers saved for this draw.'))
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 24),
              itemCount: prizeGroups.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final group = prizeGroups[index];
                return _PrizeSection(
                  tier: group.key,
                  winners: group.value,
                );
              },
            ),
    );
  }
}

class _PrizeSection extends StatelessWidget {
  const _PrizeSection({required this.tier, required this.winners});

  final String tier;
  final List<LotteryPrizeWinner> winners;

  @override
  Widget build(BuildContext context) {
    final endingNumbers = winners.every(
      (winner) => RegExp(r'^\d{4}$').hasMatch(winner.winningNumber),
    );
    final amount = winners.first.prizeAmount;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFDCE3E9)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: _brandBlue,
            child: Text(
              tier.toLowerCase().startsWith('cons')
                  ? 'Consolation Prize'
                  : '$tier Prize',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Text(
              amount == null
                  ? 'Prize amount unavailable'
                  : '${_formatRupees(amount)}/-',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF15212C),
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: winners.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: endingNumbers ? 4 : 2,
              mainAxisExtent: 48,
            ),
            itemBuilder: (context, index) {
              final winner = winners[index];
              return Container(
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  border: Border(
                    top: BorderSide(color: Color(0xFFD4D7DA), width: 0.6),
                    right: BorderSide(color: Color(0xFFD4D7DA), width: 0.6),
                  ),
                ),
                child: Text(
                  _formatWinningNumber(winner.winningNumber),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF17212C),
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  static String _formatWinningNumber(String number) {
    final serial = RegExp(r'^([A-Z]{2})(\d{6})$').firstMatch(number);
    return serial == null ? number : '${serial.group(1)} ${serial.group(2)}';
  }

  static String _formatRupees(int amount) {
    final digits = amount.toString();
    if (digits.length <= 3) return '₹ $digits';

    var prefix = digits.substring(0, digits.length - 3);
    var grouped = digits.substring(digits.length - 3);
    while (prefix.length > 2) {
      grouped = '${prefix.substring(prefix.length - 2)},$grouped';
      prefix = prefix.substring(0, prefix.length - 2);
    }
    return '₹ $prefix,$grouped';
  }
}

class BarcodeScannerPage extends StatefulWidget {
  const BarcodeScannerPage({super.key});

  @override
  State<BarcodeScannerPage> createState() => _BarcodeScannerPageState();
}

class _BarcodeScannerPageState extends State<BarcodeScannerPage> {
  bool _hasScanned = false;

  void _onDetect(BarcodeCapture capture) {
    if (_hasScanned) return;
    final value = capture.barcodes
        .map((barcode) => barcode.rawValue)
        .whereType<String>()
        .firstWhere((value) => value.trim().isNotEmpty, orElse: () => '');
    if (value.isEmpty) return;
    _hasScanned = true;
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF101812),
      appBar: AppBar(
        backgroundColor: const Color(0xFF101812),
        foregroundColor: Colors.white,
        title: const Text('Scan ticket barcode',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(onDetect: _onDetect),
          Center(
            child: Container(
              width: 280,
              height: 190,
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFB8E3A9), width: 3),
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),
          Positioned(
            left: 25,
            right: 25,
            bottom: 38,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0x9E000000),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Text(
                'Fit the barcode inside the frame',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
