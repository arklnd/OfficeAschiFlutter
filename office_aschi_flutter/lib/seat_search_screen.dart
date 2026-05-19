import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'api_service.dart';
import 'models.dart';

enum SeatFilter { all, vacant, engaged }

class SeatSearchScreen extends StatefulWidget {
  const SeatSearchScreen({super.key});

  @override
  State<SeatSearchScreen> createState() => _SeatSearchScreenState();
}

class _SeatSearchScreenState extends State<SeatSearchScreen> {
  final ApiService _api = ApiService();
  final TextEditingController _searchController = TextEditingController();

  List<SeatOverviewResponse> _allSeats = [];
  bool _loading = true;
  String? _error;
  DateTime _selectedDate = DateTime.now();
  SeatFilter _activeFilter = SeatFilter.all;

  String get _dateString => DateFormat('yyyy-MM-dd').format(_selectedDate);

  List<SeatOverviewResponse> get _filteredSeats {
    var seats = _allSeats;
    final q = _searchController.text.toLowerCase().trim();
    if (q.isNotEmpty) {
      seats = seats
          .where(
            (s) =>
                s.label.toLowerCase().contains(q) ||
                s.teamName.toLowerCase().contains(q),
          )
          .toList();
    }
    switch (_activeFilter) {
      case SeatFilter.engaged:
        return seats.where((s) => s.isEngaged).toList();
      case SeatFilter.vacant:
        return seats.where((s) => !s.isEngaged).toList();
      case SeatFilter.all:
        return seats;
    }
  }

  int get _vacantCount => _allSeats.where((s) => !s.isEngaged).length;
  int get _engagedCount => _allSeats.where((s) => s.isEngaged).length;

  @override
  void initState() {
    super.initState();
    _loadSeats();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadSeats() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final seats = await _api.getAllSeats(_dateString);
      setState(() {
        _allSeats = seats;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _onDateChange(int delta) {
    setState(() => _selectedDate = _selectedDate.add(Duration(days: delta)));
    _loadSeats();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
      _loadSeats();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final filtered = _filteredSeats;

    return Scaffold(
      appBar: AppBar(title: const Text('Seat Search')),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: SearchBar(
              controller: _searchController,
              hintText: 'Search by seat label or team...',
              leading: const Icon(Icons.search),
              trailing: [
                if (_searchController.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _searchController.clear();
                      setState(() {});
                    },
                  ),
              ],
              onChanged: (_) => setState(() {}),
            ),
          ),
          // Date selector
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => _onDateChange(-1),
                ),
                GestureDetector(
                  onTap: _pickDate,
                  child: Column(
                    children: [
                      Text(
                        DateFormat('d').format(_selectedDate),
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        DateFormat('MMM yyyy').format(_selectedDate),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      Text(
                        DateFormat('EEEE').format(_selectedDate),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => _onDateChange(1),
                ),
              ],
            ),
          ),
          // Filter chips
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                _buildFilterChip(
                  'All (${_allSeats.length})',
                  SeatFilter.all,
                  cs,
                ),
                const SizedBox(width: 8),
                _buildFilterChip(
                  'Vacant ($_vacantCount)',
                  SeatFilter.vacant,
                  cs,
                ),
                const SizedBox(width: 8),
                _buildFilterChip(
                  'Engaged ($_engagedCount)',
                  SeatFilter.engaged,
                  cs,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Content
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadSeats,
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.cloud_off_rounded,
                            size: 48,
                            color: cs.onSurfaceVariant,
                          ),
                          const SizedBox(height: 8),
                          Text(_error!),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: _loadSeats,
                            icon: const Icon(Icons.refresh, size: 18),
                            label: const Text('Try Again'),
                          ),
                        ],
                      ),
                    )
                  : filtered.isEmpty
                  ? ListView(
                      children: [
                        const SizedBox(height: 100),
                        Center(
                          child: Column(
                            children: [
                              Icon(
                                Icons.event_seat,
                                size: 48,
                                color: cs.onSurfaceVariant,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'No seats found. Adjust your search or filter.',
                                style: TextStyle(color: cs.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                      ],
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 300,
                            childAspectRatio: 2.0,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                          ),
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final seat = filtered[index];
                        return _buildSeatCard(seat, cs, isDark);
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, SeatFilter filter, ColorScheme cs) {
    final selected = _activeFilter == filter;
    return FilterChip(
      label: Text(
        label,
        style: TextStyle(color: selected ? cs.onPrimary : cs.onSurface),
      ),
      selected: selected,
      onSelected: (_) => setState(() => _activeFilter = filter),
      selectedColor: cs.primary,
      checkmarkColor: cs.onPrimary,
      backgroundColor: cs.surfaceContainerHighest,
    );
  }

  Widget _buildSeatCard(
    SeatOverviewResponse seat,
    ColorScheme cs,
    bool isDark,
  ) {
    final engaged = seat.isEngaged;
    final bgColor = engaged
        ? (isDark ? cs.primaryContainer.withOpacity(0.4) : cs.primaryContainer)
        : (isDark ? const Color(0xFF1B3A2A) : const Color(0xFFD4F5DC));
    final borderColor = engaged
        ? cs.primary
        : (isDark ? const Color(0xFF2E7D50) : const Color(0xFF43A047));

    return Card(
      color: bgColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: borderColor, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    seat.label,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: engaged
                        ? cs.error.withOpacity(0.15)
                        : const Color(0xFF1B6B35).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    engaged ? 'Engaged' : 'Vacant',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: engaged ? cs.error : const Color(0xFF2E7D50),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              seat.teamName,
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              overflow: TextOverflow.ellipsis,
            ),
            const Spacer(),
            if (engaged && seat.engagedBy != null)
              Row(
                children: [
                  CircleAvatar(
                    radius: 12,
                    backgroundColor: cs.primary,
                    child: Text(
                      seat.engagedBy!.reporteeName[0].toUpperCase(),
                      style: TextStyle(
                        color: cs.onPrimary,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      seat.engagedBy!.reporteeName,
                      style: const TextStyle(fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
