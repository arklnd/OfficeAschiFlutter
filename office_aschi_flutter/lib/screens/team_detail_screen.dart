import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../models/models.dart';
import '../utils/clipboard_otp_mixin.dart';
import '../widgets/seat_booking_card.dart';
import '../widgets/date_navigator.dart';
import '../widgets/availability_stats.dart';
import '../widgets/waitlist_card.dart';
import '../widgets/manage_seats_card.dart';
import '../widgets/pending_approvals_card.dart';
import '../widgets/member_list_card.dart';
import '../widgets/danger_zone_card.dart';
import '../dialogs/totp_prompt_dialog.dart';
import '../dialogs/join_team_dialog.dart';
import '../dialogs/book_seat_dialog.dart';

class TeamDetailScreen extends StatefulWidget {
  final int teamId;
  const TeamDetailScreen({super.key, required this.teamId});

  @override
  State<TeamDetailScreen> createState() => _TeamDetailScreenState();
}

class _TeamDetailScreenState extends State<TeamDetailScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver, ClipboardOtpMixin {
  final ApiService _api = ApiService();
  late TabController _tabController;

  TeamResponse? _team;
  List<SeatResponse> _seats = [];
  List<ReporteeResponse> _reportees = [];
  AvailabilityResponse? _availability;
  bool _loading = true;
  bool _availabilityLoading = false;
  bool _notFound = false;
  String? _availabilityError;
  DateTime _selectedDate = DateTime.now();
  final TextEditingController _seatLabelCtrl = TextEditingController();
  int? _currentReporteeId;
  late final StreamSubscription _recoverySub;

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
    WidgetsBinding.instance.addObserver(this);
    initClipboardOtp();
    _tabController = TabController(length: 2, vsync: this);
    _loadCurrentReporteeId();
    _loadAll();
    _recoverySub = _api.backendRecovered.stream.listen((_) => _loadAll());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    handleLifecycleForOtp(state);
  }

  Future<void> _loadCurrentReporteeId() async {
    final prefs = await SharedPreferences.getInstance();
    final savedId = prefs.getInt('reportee_${widget.teamId}');
    if (savedId != null && mounted) {
      setState(() => _currentReporteeId = savedId);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    disposeClipboardOtp();
    _recoverySub.cancel();
    _tabController.dispose();
    _seatLabelCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Data loading
  // ---------------------------------------------------------------------------

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
    setState(() {
      _availabilityLoading = true;
      _availabilityError = null;
      _availability = null;
    });
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
        _availabilityError = _api.noInternet.value
            ? 'No internet connection'
            : 'Unable to load availability';
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Date navigation
  // ---------------------------------------------------------------------------

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

  // ---------------------------------------------------------------------------
  // Actions (business logic delegated to dialogs / api)
  // ---------------------------------------------------------------------------

  Future<String?> _promptTotp(String title, {String? entityName, String? reason}) async {
    final result = await showTotpPromptDialog(
      context,
      title: title,
      entityName: entityName,
      reason: reason,
      clipboardOtp: clipboardOtp,
      pasteClipboardCode: pasteClipboardCode,
      launchAuthenticator: launchAuthenticator,
    );
    resetClipboardOtp();
    return result;
  }

  void _openBookDialog(int seatId, String seatLabel) async {
    final bookedIds = (_availability?.bookings ?? [])
        .map((b) => b.reporteeId)
        .toSet();
    final availableReportees = _approvedReportees
        .where((r) => !bookedIds.contains(r.id))
        .toList();

    final success = await showBookSeatDialog(
      context,
      seatId: seatId,
      seatLabel: seatLabel,
      selectedDate: _selectedDate,
      availableReportees: availableReportees,
      currentReporteeId: _currentReporteeId,
      clipboardOtp: clipboardOtp,
      pasteClipboardCode: pasteClipboardCode,
      launchAuthenticator: launchAuthenticator,
    );
    resetClipboardOtp();
    if (success == true) _loadAvailability();
  }

  void _cancelBooking(BookingResponse booking) async {
    final confirmed = await showConfirmActionDialog(
      context,
      title: 'Cancel Booking',
      message: 'Cancel booking for ${booking.reporteeName} on ${booking.seatLabel}?',
      confirmLabel: 'Yes, cancel',
      cancelLabel: 'No',
      isDestructive: true,
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Booking cancelled')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Seat "$label" added')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Seat "${seat.label}" deleted')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Member approved')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

  void _denyReportee(ReporteeResponse r) async {
    final confirmed = await showConfirmActionDialog(
      context,
      title: 'Deny Join Request',
      message: 'Deny ${r.friendlyName} from joining?',
      confirmLabel: 'Deny',
      isDestructive: true,
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Denied ${r.friendlyName}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

  void _removeReportee(ReporteeResponse r) async {
    final confirmed = await showConfirmActionDialog(
      context,
      title: 'Remove Member',
      message: 'Remove ${r.friendlyName} and all their bookings?',
      confirmLabel: 'Remove',
      isDestructive: true,
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Removed ${r.friendlyName}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

  void _deleteTeam() async {
    final confirmed = await showConfirmActionDialog(
      context,
      title: 'Delete Team',
      message: 'Delete "${_team?.name}" and all its data? This cannot be undone.',
      confirmLabel: 'Delete',
      isDestructive: true,
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Team deleted')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

  void _openJoinDialog() async {
    final reporteeId = await showJoinTeamDialog(
      context,
      teamId: widget.teamId,
      teamName: _team?.name,
      clipboardOtp: clipboardOtp,
      pasteClipboardCode: pasteClipboardCode,
      launchAuthenticatorWithUri: launchAuthenticatorWithUri,
    );
    resetClipboardOtp();
    if (reporteeId != null) {
      _currentReporteeId = reporteeId;
      _loadAll();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Join request sent! Awaiting manager approval.')),
        );
      }
    }
  }

  void _copyTeamUrl() {
    Clipboard.setData(
      ClipboardData(
        text: 'https://officeaschi.azurewebsites.net/team/${widget.teamId}',
      ),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Team link copied!')),
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

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
              FilledButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Back to Teams'),
              ),
            ],
          ),
        ),
      );
    }

    final cs = Theme.of(context).colorScheme;
    final pendingCount = _pendingReportees.length;
    return Scaffold(
      appBar: AppBar(
        title: Text(_team?.name ?? 'Loading...'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: _copyTeamUrl,
            tooltip: 'Copy team link',
            style: IconButton.styleFrom(
              backgroundColor: cs.primaryContainer,
              foregroundColor: cs.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            icon: const Icon(Icons.person_add),
            onPressed: _openJoinDialog,
            tooltip: 'Join team',
            style: IconButton.styleFrom(
              backgroundColor: cs.primaryContainer,
              foregroundColor: cs.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: 8),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            const Tab(text: 'Bookings', icon: Icon(Icons.calendar_today)),
            Tab(
              text: 'Manage',
              icon: Badge(
                isLabelVisible: pendingCount > 0,
                label: Text('$pendingCount'),
                child: const Icon(Icons.settings),
              ),
            ),
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

  // ---------------------------------------------------------------------------
  // Bookings Tab
  // ---------------------------------------------------------------------------

  Widget _buildBookingsTab() {
    return RefreshIndicator(
      onRefresh: _loadAvailability,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DateNavigator(
            selectedDate: _selectedDate,
            onPreviousDay: _goToPreviousDay,
            onNextDay: _goToNextDay,
            onToday: _isToday ? null : _goToToday,
            onDatePicked: (picked) {
              setState(() => _selectedDate = picked);
              _loadAvailability();
            },
          ),
          const SizedBox(height: 16),
          AvailabilityStats(availability: _availability),
          const SizedBox(height: 16),
          _availabilityLoading
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: CircularProgressIndicator(),
                  ),
                )
              : _availabilityError != null
              ? _buildAvailabilityError()
              : _buildSeatGrid(),
          if ((_availability?.waitlist ?? []).isNotEmpty) ...[
            const SizedBox(height: 24),
            WaitlistCard(waitlist: _availability!.waitlist),
          ],
        ],
      ),
    );
  }

  Widget _buildAvailabilityError() {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.errorContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              _api.noInternet.value
                  ? Icons.wifi_off_rounded
                  : Icons.cloud_off_rounded,
              size: 36,
              color: cs.onErrorContainer,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _availabilityError!,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Tap retry to reload bookings for this date.',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _loadAvailability,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Retry'),
          ),
        ],
      ),
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
        final aspectRatio = crossAxisCount == 1 ? 3.5 : 1.8;
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
            return SeatBookingCard(
              seat: seat,
              onBook: () => _openBookDialog(seat.seatId, seat.label),
              onCancel: seat.booking != null
                  ? () => _cancelBooking(seat.booking!)
                  : null,
            );
          },
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Manage Tab
  // ---------------------------------------------------------------------------

  Widget _buildManageTab() {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        ManageSeatsCard(
          seats: _seats,
          seatLabelController: _seatLabelCtrl,
          onDeleteSeat: _deleteSeat,
          onAddSeat: _addSeat,
        ),
        const SizedBox(height: 12),
        if (_pendingReportees.isNotEmpty) ...[
          PendingApprovalsCard(
            pendingMembers: _pendingReportees,
            onApprove: _approveReportee,
            onDeny: _denyReportee,
          ),
          const SizedBox(height: 12),
        ],
        MemberListCard(
          members: _approvedReportees,
          onRemove: _removeReportee,
        ),
        const SizedBox(height: 12),
        DangerZoneCard(
          title: 'Delete this team',
          subtitle: 'Removes all seats, members, and bookings.',
          onAction: _deleteTeam,
        ),
        const SizedBox(height: 32),
      ],
    );
  }
}
