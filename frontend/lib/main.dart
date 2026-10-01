import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'lottery_service.dart';

void main() {
  runApp(const KeralaLotteryApp());
}

const _brandBlue = Color(0xFF1553A6);
const _deepBlue = Color(0xFF10458F);
const _pageBackground = Color(0xFFF1F3F6);
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
  String? _resultText;
  String? _resultFileName;
  String? _statusMessage;
  bool _isLoadingResults = false;
  bool _isLoadingSavedDraws = true;
  bool _isFetchingLatest = false;
  String? _savedResultsError;
  bool? _wasFound;

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
      setState(() => _savedResultsError = error.toString().replaceFirst('Exception: ', ''));
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
        _savedResultsError = draws.isEmpty ? 'No published lottery results are available yet.' : null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _savedResultsError = error.toString().replaceFirst('Exception: ', ''));
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
      _checkTicket();
    }
  }

  Future<void> _pickResultsPdf() async {
    final selection = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      withData: true,
    );
    if (selection == null || selection.files.isEmpty || !mounted) return;

    setState(() {
      _isLoadingResults = true;
      _resultText = null;
      _resultFileName = null;
      _statusMessage = null;
      _wasFound = null;
    });
    try {
      final file = selection.files.single;
      final text = await _lotteryService.parsePdf(file);
      if (!mounted) return;
      setState(() {
        _resultText = text;
        _resultFileName = file.name;
        _statusMessage = null;
      });
      _checkTicket();
    } catch (error) {
      if (!mounted) return;
      setState(() => _statusMessage = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoadingResults = false);
    }
  }

  void _checkTicket() {
    final results = _resultText;
    final code = _ticketController.text.trim();
    if (results == null || code.isEmpty) {
      setState(() => _wasFound = null);
      return;
    }
    setState(() => _wasFound = resultContainsTicketCode(code, results));
  }

  void _showDrawResults(LotteryDraw draw) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(draw.lotteryName),
        content: SizedBox(
          width: 400,
          height: 360,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Draw date: ${draw.drawDate}'),
              const SizedBox(height: 8),
              Expanded(
                child: draw.winners.isEmpty
                    ? const Center(child: Text('No winning numbers saved for this draw.'))
                    : ListView.separated(
                        itemCount: draw.winners.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final winner = draw.winners[index];
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(winner.prizeTier),
                            trailing: Text(
                              winner.winningNumber,
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
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
            onPressed: () => setState(() => _selectedTab = 2),
            icon: const Icon(Icons.qr_code_scanner, size: 21),
          ),
        ],
      ),
      drawer: _buildDrawer(),
      body: IndexedStack(
        index: _selectedTab,
        children: [
          _buildHomePage(),
          _buildSearchPage(),
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
          BottomNavigationBarItem(icon: Icon(Icons.home_outlined), activeIcon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.search), label: 'Search'),
          BottomNavigationBarItem(icon: Icon(Icons.qr_code_scanner), label: 'Scan'),
          BottomNavigationBarItem(icon: Icon(Icons.insights_outlined), label: 'Prediction'),
        ],
      ),
    );
  }

  Widget _buildHomePage() {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
            child: Column(
              children: [
                const Text(
                  'welcome',
                  style: TextStyle(fontSize: 11, color: Color(0xFF78818D)),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Recent saved results',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF26364B),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Tap a draw to view its winning numbers',
                  style: TextStyle(fontSize: 11, color: Colors.blueGrey.shade500),
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Align(
              alignment: Alignment.centerRight,
              child: IconButton.filledTonal(
                tooltip: _lotteryService.usesPublishedResults
                    ? 'Refresh published results'
                    : 'Fetch latest official result',
                onPressed: _isFetchingLatest ? null : _fetchLatestDraw,
                icon: _isFetchingLatest
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync, size: 19),
              ),
            ),
          ),
        ),
        if (_savedResultsError != null && _savedDraws.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Text(
                _savedResultsError!,
                style: const TextStyle(color: Color(0xFF9B2929), fontSize: 12),
              ),
            ),
          ),
        if (_isLoadingSavedDraws)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_savedDraws.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _buildEmptyResults(),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
            sliver: _buildDrawGrid(_savedDraws),
          ),
      ],
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
              _savedResultsError == null ? Icons.inbox_outlined : Icons.cloud_off_outlined,
              size: 38,
              color: const Color(0xFF78818D),
            ),
            const SizedBox(height: 10),
            Text(
              _savedResultsError == null ? 'No saved results yet' : 'Could not load results',
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
                    : Icon(_lotteryService.usesPublishedResults ? Icons.sync : Icons.download_outlined),
                  label: Text(
                  _isFetchingLatest
                    ? (_lotteryService.usesPublishedResults ? 'Refreshing...' : 'Fetching...')
                    : (_lotteryService.usesPublishedResults ? 'Refresh results' : 'Fetch latest result'),
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchPage() {
    final filteredDraws = _savedDraws
        .where((draw) => draw.lotteryName.contains(_searchQuery.trim().toUpperCase()))
        .toList();
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
            child: TextField(
              onChanged: (value) => setState(() => _searchQuery = value),
              decoration: InputDecoration(
                hintText: 'Search lottery draws',
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        ),
        if (filteredDraws.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: Text('No matching saved results')),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
            sliver: _buildDrawGrid(filteredDraws),
          ),
      ],
    );
  }

  SliverGrid _buildDrawGrid(List<LotteryDraw> draws) {
    return SliverGrid.builder(
      itemCount: draws.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        mainAxisExtent: 86,
      ),
      itemBuilder: (context, index) => _drawTile(draws[index], index),
    );
  }

  Widget _drawTile(LotteryDraw draw, int index) {
    final shades = [
      _brandBlue,
      const Color(0xFF1B5DB5),
      const Color(0xFF2056A0),
      const Color(0xFF164A98),
    ];
    final color = shades[index % shades.length];
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(5),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showDrawResults(draw),
        child: Column(
          children: [
            Expanded(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned(
                    top: 5,
                    left: 5,
                    child: _tileTag('DRAW'),
                  ),
                  Positioned(
                    top: 5,
                    right: 5,
                    child: _tileTag('RESULTS'),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 19),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          draw.lotteryName,
                          maxLines: 1,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            height: 1.12,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${draw.drawDate} | ${draw.winners.length} numbers',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white70, fontSize: 8),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Container(
              height: 25,
              width: double.infinity,
              color: Colors.white,
              alignment: Alignment.center,
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'VIEW NUMBERS',
                    style: TextStyle(
                      color: Color(0xFF344256),
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(width: 4),
                  Icon(Icons.chevron_right, size: 13, color: _brandBlue),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tileTag(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0x33FFFFFF),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 6,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildCheckerPage() {
    final hasResults = _resultText != null;
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
          InkWell(
            onTap: _isLoadingResults ? null : _pickResultsPdf,
            borderRadius: BorderRadius.circular(6),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFFD8DEE7)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE9F0FA),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Icon(
                      _isLoadingResults ? Icons.hourglass_top : Icons.picture_as_pdf_outlined,
                      color: _brandBlue,
                      size: 21,
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isLoadingResults
                              ? 'Reading results...'
                              : hasResults
                                  ? 'Results loaded'
                                  : 'Choose result PDF',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF26364B),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _resultFileName ?? 'Select an official draw PDF',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: Color(0xFF78818D)),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Color(0xFF78818D)),
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
              label: const Text('Scan barcode'),
              style: FilledButton.styleFrom(
                backgroundColor: _brandBlue,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
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
            onChanged: (_) => _checkTicket(),
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              hintText: 'Ticket / barcode value',
              prefixIcon: const Icon(Icons.confirmation_number_outlined, size: 20),
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
          if (_statusMessage != null) ...[
            const SizedBox(height: 12),
            _notice(_statusMessage!, isError: true),
          ],
          if (_wasFound != null) ...[
            const SizedBox(height: 12),
            _notice(
              _wasFound!
                  ? 'This value appears in the uploaded result text.'
                  : 'No exact match found in the uploaded result text.',
              isError: !_wasFound!,
            ),
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
                    'A barcode may contain a serial number, not the winning number. This checks for a text match only; confirm results with the official Kerala State Lotteries publication.',
                    style: TextStyle(fontSize: 11, height: 1.4, color: Color(0xFF52647A)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
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
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Color(0xFF26364B)),
            ),
            const SizedBox(height: 7),
            const Text(
              'Lottery draws are random. Use official results to check your ticket.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, height: 1.4, color: Color(0xFF78818D)),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => setState(() => _selectedTab = 2),
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
          child: Text('Ponkudam', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        ),
        NavigationDrawerDestination(icon: Icon(Icons.home_outlined), label: Text('Home')),
        NavigationDrawerDestination(icon: Icon(Icons.search), label: Text('Search')),
        NavigationDrawerDestination(icon: Icon(Icons.qr_code_scanner), label: Text('Scan')),
        NavigationDrawerDestination(icon: Icon(Icons.insights_outlined), label: Text('Prediction')),
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
          Icon(isError ? Icons.search_off : Icons.check_circle_outline, color: color, size: 19),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 12, height: 1.35, color: color, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
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
        title: const Text('Scan ticket barcode', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
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
