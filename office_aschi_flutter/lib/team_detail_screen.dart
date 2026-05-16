import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'api_service.dart';
import 'models.dart';
import 'package:intl/intl.dart';

class TeamDetailScreen extends StatefulWidget {
  final int teamId;
  const TeamDetailScreen({super.key, required this.teamId});

  @override
  State<TeamDetailScreen> createState() => _TeamDetailScreenState();
}

class _TeamDetailScreenState extends State<TeamDetailScreen>
    with SingleTickerProviderStateMixin {
  final ApiService _api = ApiService();
  late TabController _tabController;

  TeamResponse? _team;
  List<SeatResponse> _seats = [];
  List<ReporteeResponse> _reportees = [];
  AvailabilityResponse? _availability;
  bool _loading = true;
  bool _availabilityLoading = false;
  bool _notFound = false;
  DateTime _selectedDate = DateTime.now();
  final TextEditingController _seatLabelCtrl = TextEditingController();

  List<ReporteeResponse> get _approvedReportees =>
      _reportees.where((r) => r.isApproved).toList();
  List<ReporteeResponse> get _pendingReportees =>
      _reportees.where((r) => !r.isApproved).toList();

  List<SeatView> get _allSeats {
    final booked = (_availability?.bookings ?? []).map(
      (b) => SeatView(
        seatId: b.seatId,
        label: b.seatLabel,
        status: 'booked',
        personName: b.reporteeName,
        booking: b,
      ),
    );
    final available = (_availability?.availableSeats ?? []).map(
      (s) => SeatView(seatId: s.id, label: s.label, status: 'available'),
    );
    return [...booked, ...available];
  }

  String get _dateString => DateFormat('yyyy-MM-dd').format(_selectedDate);
  bool get _isToday =>
      DateFormat('yyyy-MM-dd').format(_selectedDate) ==
      DateFormat('yyyy-MM-dd').format(DateTime.now());

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _seatLabelCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _notFound = false;
    });
    try {
      final results = await Future.wait([
        _api.getTeam(widget.teamId),
        _api.listSeats(widget.teamId),
        _api.listReportees(widget.teamId),
      ]);
      setState(() {
        _team = results[0] as TeamResponse;
        _seats = results[1] as List<SeatResponse>;
        _reportees = results[2] as List<ReporteeResponse>;
      });
      await _loadAvailability();
    } catch (e) {
      setState(() {
        _notFound = true;
        _loading = false;
      });
    }
  }

  Future<void> _loadAvailability() async {
    setState(() => _availabilityLoading = true);
    try {
      final avail = await _api.getAvailability(widget.teamId, _dateString);
      setState(() {
        _availability = avail;
        _availabilityLoading = false;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _availabilityLoading = false;
        _loading = false;
      });
    }
  }

  void _goToPreviousDay() {
    setState(
      () => _selectedDate = _selectedDate.subtract(const Duration(days: 1)),
    );
    _loadAvailability();
  }

  void _goToNextDay() {
    setState(() => _selectedDate = _selectedDate.add(const Duration(days: 1)));
    _loadAvailability();
  }

  void _goToToday() {
    setState(() => _selectedDate = DateTime.now());
    _loadAvailability();
  }

  Future<String?> _promptTotp(
    String title, {
    String? entityName,
    String? reason,
  }) async {
    final codeCtrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (entityName != null && reason != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text.rich(
                  TextSpan(
                    children: [
                      const TextSpan(text: 'Enter the 6-digit TOTP code for '),
                      TextSpan(
                        text: entityName,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      TextSpan(text: ' to ${reason.toLowerCase()}.'),
                    ],
                  ),
                ),
              ),
            TextField(
              controller: codeCtrl,
              decoration: const InputDecoration(
                labelText: 'TOTP Code',
                hintText: '6-digit code',
              ),
              keyboardType: TextInputType.number,
              maxLength: 6,
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, codeCtrl.text),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  void _openBookDialog(int seatId, String seatLabel) {
    final bookedIds = (_availability?.bookings ?? [])
        .map((b) => b.reporteeId)
        .toSet();
    final availableReportees = _approvedReportees
        .where((r) => !bookedIds.contains(r.id))
        .toList();

    if (availableReportees.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No available members to book')),
      );
      return;
    }

    ReporteeResponse? selected = availableReportees.first;
    final codeCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Book $seatLabel'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Date: ${DateFormat('EEE, MMM d').format(_selectedDate)}'),
              const SizedBox(height: 12),
              DropdownButtonFormField<ReporteeResponse>(
                value: selected,
                decoration: const InputDecoration(labelText: 'Select Person'),
                items: availableReportees
                    .map(
                      (r) => DropdownMenuItem(
                        value: r,
                        child: Text(r.friendlyName),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setDialogState(() => selected = v),
              ),
              const SizedBox(height: 8),
              Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(text: 'Enter the 6-digit TOTP code for '),
                    TextSpan(
                      text: selected?.friendlyName ?? '',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const TextSpan(text: ' to book seat.'),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: codeCtrl,
                decoration: const InputDecoration(labelText: 'TOTP Code'),
                keyboardType: TextInputType.number,
                maxLength: 6,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (selected == null || codeCtrl.text.isEmpty) return;
                try {
                  await _api.bookSeat(
                    selected!.id,
                    seatId,
                    _dateString,
                    codeCtrl.text,
                  );
                  if (ctx.mounted) Navigator.pop(ctx);
                  _loadAvailability();
                  if (mounted)
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Booked ${selected!.friendlyName} on $seatLabel',
                        ),
                      ),
                    );
                } catch (e) {
                  if (ctx.mounted)
                    ScaffoldMessenger.of(
                      ctx,
                    ).showSnackBar(SnackBar(content: Text(e.toString())));
                }
              },
              child: const Text('Book'),
            ),
          ],
        ),
      ),
    );
  }

  void _cancelBooking(BookingResponse booking) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Booking'),
        content: Text(
          'Cancel booking for ${booking.reporteeName} on ${booking.seatLabel}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Yes, cancel'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final code = await _promptTotp(
      'Cancel Booking',
      entityName: booking.reporteeName,
      reason: 'Cancel booking',
    );
    if (code == null || code.isEmpty) return;
    try {
      await _api.cancelBooking(booking.id, booking.reporteeId, code);
      _loadAvailability();
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Booking cancelled')));
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  void _addSeat() async {
    final label = _seatLabelCtrl.text.trim();
    if (label.isEmpty) return;
    final code = await _promptTotp(
      'Add Seat',
      entityName: _team?.name ?? '',
      reason: 'Add seat',
    );
    if (code == null || code.isEmpty) return;
    try {
      await _api.addSeat(widget.teamId, label, code);
      _seatLabelCtrl.clear();
      _loadAll();
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Seat "$label" added')));
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  void _deleteSeat(SeatResponse seat) async {
    final code = await _promptTotp(
      'Delete Seat',
      entityName: _team?.name ?? '',
      reason: 'Delete seat',
    );
    if (code == null || code.isEmpty) return;
    try {
      await _api.deleteSeat(widget.teamId, seat.id, code);
      _loadAll();
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Seat "${seat.label}" deleted')));
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  void _approveReportee(int reporteeId) async {
    final code = await _promptTotp(
      'Approve Member',
      entityName: _team?.name ?? '',
      reason: 'Approve member',
    );
    if (code == null || code.isEmpty) return;
    try {
      await _api.approveReportee(widget.teamId, reporteeId, code);
      _loadAll();
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Member approved')));
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  void _denyReportee(ReporteeResponse r) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Deny Join Request'),
        content: Text('Deny ${r.friendlyName} from joining?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Deny'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final code = await _promptTotp(
      'Deny Join Request',
      entityName: _team?.name ?? '',
      reason: 'Deny join request',
    );
    if (code == null || code.isEmpty) return;
    try {
      await _api.denyReportee(widget.teamId, r.id, code);
      _loadAll();
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Denied ${r.friendlyName}')));
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  void _removeReportee(ReporteeResponse r) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Member'),
        content: Text('Remove ${r.friendlyName} and all their bookings?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final code = await _promptTotp(
      'Remove Member',
      entityName: _team?.name ?? '',
      reason: 'Remove member',
    );
    if (code == null || code.isEmpty) return;
    try {
      await _api.removeReportee(widget.teamId, r.id, code);
      _loadAll();
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Removed ${r.friendlyName}')));
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  void _deleteTeam() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Team'),
        content: Text(
          'Delete "${_team?.name}" and all its data? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final code = await _promptTotp(
      'Delete Team',
      entityName: _team?.name ?? '',
      reason: 'Delete team',
    );
    if (code == null || code.isEmpty) return;
    try {
      await _api.deleteTeam(widget.teamId, code);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Team deleted')));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  void _openJoinDialog() {
    final nameCtrl = TextEditingController();
    final secretCtrl = TextEditingController();
    final codeCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Join Team'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Your Name'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: secretCtrl,
              decoration: const InputDecoration(labelText: 'TOTP Secret Key'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: codeCtrl,
              decoration: const InputDecoration(labelText: 'TOTP Code'),
              keyboardType: TextInputType.number,
              maxLength: 6,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                await _api.joinTeam(
                  widget.teamId,
                  nameCtrl.text,
                  secretCtrl.text,
                  codeCtrl.text,
                );
                if (ctx.mounted) Navigator.pop(ctx);
                _loadAll();
                if (mounted)
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Join request sent! Awaiting manager approval.',
                      ),
                    ),
                  );
              } catch (e) {
                if (ctx.mounted)
                  ScaffoldMessenger.of(
                    ctx,
                  ).showSnackBar(SnackBar(content: Text(e.toString())));
              }
            },
            child: const Text('Join'),
          ),
        ],
      ),
    );
  }

  void _copyTeamUrl() {
    Clipboard.setData(ClipboardData(text: 'team/${widget.teamId}'));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Team link copied!')));
  }

  @override
  Widget build(BuildContext context) {
    if (_notFound) {
      return Scaffold(
        appBar: AppBar(title: const Text('Team Not Found')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 64),
              const SizedBox(height: 16),
              const Text('Team not found', style: TextStyle(fontSize: 20)),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Back to Teams'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_team?.name ?? 'Loading...'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: _copyTeamUrl,
            tooltip: 'Copy team link',
          ),
          IconButton(
            icon: const Icon(Icons.person_add),
            onPressed: _openJoinDialog,
            tooltip: 'Join team',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Bookings', icon: Icon(Icons.calendar_today)),
            Tab(text: 'Manage', icon: Icon(Icons.settings)),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [_buildBookingsTab(), _buildManageTab()],
            ),
    );
  }

  // ===================== BOOKINGS TAB =====================
  Widget _buildBookingsTab() {
    return RefreshIndicator(
      onRefresh: _loadAvailability,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Date navigator
          _buildDateHero(),
          const SizedBox(height: 16),
          // Stats
          _buildStats(),
          const SizedBox(height: 16),
          // Seat Grid
          _availabilityLoading
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: CircularProgressIndicator(),
                  ),
                )
              : _buildSeatGrid(),
          // Waitlist
          if ((_availability?.waitlist ?? []).isNotEmpty) ...[
            const SizedBox(height: 24),
            _buildWaitlist(),
          ],
        ],
      ),
    );
  }

  Widget _buildDateHero() {
    return Row(
      children: [
        IconButton(
          onPressed: _goToPreviousDay,
          icon: const Icon(Icons.chevron_left),
        ),
        InkWell(
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: _selectedDate,
              firstDate: DateTime(2024),
              lastDate: DateTime(2030),
            );
            if (picked != null) {
              setState(() => _selectedDate = picked);
              _loadAvailability();
            }
          },
          child: Column(
            children: [
              Text(
                '${_selectedDate.day}',
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '${DateFormat('MMM').format(_selectedDate)} ${_selectedDate.year}',
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                DateFormat('EEEE').format(_selectedDate),
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: _goToNextDay,
          icon: const Icon(Icons.chevron_right),
        ),
        if (!_isToday)
          TextButton.icon(
            onPressed: _goToToday,
            icon: const Icon(Icons.today, size: 18),
            label: const Text('Today'),
          ),
      ],
    );
  }

  Widget _buildStats() {
    final a = _availability;
    return Wrap(
      spacing: 8,
      children: [
        _StatChip(label: '${a?.bookedCount ?? 0} booked', color: Colors.blue),
        _StatChip(
          label: '${a?.availableCount ?? 0} available',
          color: Colors.green,
        ),
        if ((a?.waitlistedCount ?? 0) > 0)
          _StatChip(
            label: '${a!.waitlistedCount} waitlisted',
            color: Colors.orange,
          ),
        _StatChip(label: '${a?.totalSeats ?? 0} total', color: Colors.grey),
      ],
    );
  }

  Widget _buildSeatGrid() {
    final seats = _allSeats;
    if (seats.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'No seats configured yet. Go to Manage tab to add seats.',
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 800
            ? 4
            : constraints.maxWidth > 500
            ? 3
            : constraints.maxWidth > 350
            ? 2
            : 1;
        final aspectRatio = crossAxisCount == 1 ? 2.5 : 1.4;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: aspectRatio,
          ),
          itemCount: seats.length,
          itemBuilder: (context, index) {
            final seat = seats[index];
            final isBooked = seat.status == 'booked';
            final cs = Theme.of(context).colorScheme;
            final isDark = Theme.of(context).brightness == Brightness.dark;
            return Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: isBooked
                      ? cs.primary.withOpacity(0.4)
                      : Colors.green.withOpacity(isDark ? 0.4 : 0.3),
                  width: 1.5,
                ),
              ),
              color: isBooked
                  ? cs.primaryContainer.withOpacity(isDark ? 0.3 : 1.0)
                  : cs.surface,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            seat.label,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        if (isBooked)
                          IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () => _cancelBooking(seat.booking!),
                            tooltip: 'Cancel booking',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                      ],
                    ),
                    const Spacer(),
                    if (isBooked)
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 14,
                            backgroundColor: cs.primary,
                            child: Text(
                              seat.personName.isNotEmpty
                                  ? seat.personName[0].toUpperCase()
                                  : '?',
                              style: TextStyle(
                                color: cs.onPrimary,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              seat.personName,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      )
                    else
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () =>
                              _openBookDialog(seat.seatId, seat.label),
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('Book'),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildWaitlist() {
    final waitlist = _availability?.waitlist ?? [];
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.orange.withOpacity(0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Waitlist',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            ...waitlist.asMap().entries.map((entry) {
              final i = entry.key;
              final w = entry.value;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: Colors.orange,
                  child: Text(
                    '${i + 1}',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                title: Text(w.reporteeName),
                subtitle: Text('Waiting for ${w.desiredSeatLabel}'),
              );
            }),
          ],
        ),
      ),
    );
  }

  // ===================== MANAGE TAB =====================
  Widget _buildManageTab() {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        _buildManageSeats(),
        const SizedBox(height: 12),
        if (_pendingReportees.isNotEmpty) ...[
          _buildPendingApprovals(),
          const SizedBox(height: 12),
        ],
        _buildMembersList(),
        const SizedBox(height: 12),
        _buildDangerZone(),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildManageSeats() {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        color: cs.surfaceContainerLow,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Seats',
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(color: cs.onSurfaceVariant),
              ),
              if (_seats.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _seats
                      .map(
                        (s) => InputChip(
                          label: Text(s.label),
                          onDeleted: () => _deleteSeat(s),
                        ),
                      )
                      .toList(),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _seatLabelCtrl,
                decoration: InputDecoration(
                  hintText: 'e.g. Desk A1',
                  labelText: 'New seat label',
                  border: const OutlineInputBorder(),
                  isDense: true,
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: _addSeat,
                    tooltip: 'Add seat',
                  ),
                ),
                onSubmitted: (_) => _addSeat(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPendingApprovals() {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        color: cs.surfaceContainerLow,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(
                'Pending Approvals',
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
            ..._pendingReportees.map(
              (r) => ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.orange,
                  child: Text(
                    r.friendlyName[0].toUpperCase(),
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                title: Text(r.friendlyName),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      onPressed: () => _approveReportee(r.id),
                      child: const Text('Approve'),
                    ),
                    TextButton(
                      onPressed: () => _denyReportee(r),
                      style: TextButton.styleFrom(foregroundColor: cs.error),
                      child: const Text('Deny'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildMembersList() {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        color: cs.surfaceContainerLow,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(
                'Members',
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
            if (_approvedReportees.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Text(
                  'No approved members yet.',
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              )
            else ...[
              ..._approvedReportees.asMap().entries.map((entry) {
                final i = entry.key;
                final r = entry.value;
                const colors = [
                  Colors.blue,
                  Colors.teal,
                  Colors.purple,
                  Colors.green,
                  Colors.orange,
                  Colors.cyan,
                  Colors.pink,
                  Colors.red,
                ];
                final color = colors[r.id % colors.length];
                return Column(
                  children: [
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor: color,
                        child: Text(
                          r.friendlyName[0].toUpperCase(),
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                      title: Text(r.friendlyName),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _removeReportee(r),
                        tooltip: 'Remove member',
                      ),
                    ),
                    if (i < _approvedReportees.length - 1)
                      const Divider(height: 1, indent: 72),
                  ],
                );
              }),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDangerZone() {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        color: cs.errorContainer.withOpacity(0.3),
        child: ListTile(
          leading: Icon(Icons.delete_forever, color: cs.error),
          title: Text('Delete this team', style: TextStyle(color: cs.error)),
          subtitle: const Text('Removes all seats, members, and bookings.'),
          trailing: TextButton(
            onPressed: _deleteTeam,
            style: TextButton.styleFrom(foregroundColor: cs.error),
            child: const Text('Delete'),
          ),
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final Color color;
  const _StatChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(isDark ? 0.2 : 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: isDark ? color.withOpacity(0.9) : color.withOpacity(0.8),
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
