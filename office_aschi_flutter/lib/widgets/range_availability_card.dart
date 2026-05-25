import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';

/// Card showing a date range availability grid with a range date picker.
///
/// Displays a 7-column calendar grid where each cell shows the day of week,
/// day number, utilization bar, and available/total count. Tapping a cell
/// calls [onJumpToDate] to navigate to single-day view.
class RangeAvailabilityCard extends StatelessWidget {
  final RangeAvailabilityResponse? rangeAvailability;
  final bool loading;
  final DateTime rangeFrom;
  final DateTime rangeTo;
  final ValueChanged<DateTime> onRangeFromChanged;
  final ValueChanged<DateTime> onRangeToChanged;
  final ValueChanged<String> onJumpToDate;

  const RangeAvailabilityCard({
    super.key,
    required this.rangeAvailability,
    required this.loading,
    required this.rangeFrom,
    required this.rangeTo,
    required this.onRangeFromChanged,
    required this.onRangeToChanged,
    required this.onJumpToDate,
  });

  bool _isWeekend(String dateStr) {
    final day = DateTime.parse(dateStr).weekday;
    return day == DateTime.saturday || day == DateTime.sunday;
  }

  String _dayOfWeekShort(String dateStr) {
    return DateFormat('E').format(DateTime.parse(dateStr));
  }

  int _dayOfMonth(String dateStr) {
    return DateTime.parse(dateStr).day;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Text(
              'Range Availability',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            // Date range picker row
            _buildDateRangePicker(context, cs),
            const SizedBox(height: 12),
            // Grid
            if (loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (rangeAvailability != null)
              _buildGrid(context, cs, isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildDateRangePicker(BuildContext context, ColorScheme cs) {
    return Row(
      children: [
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () async {
              final range = await showDateRangePicker(
                context: context,
                firstDate: DateTime.now().subtract(const Duration(days: 365)),
                lastDate: DateTime.now().add(const Duration(days: 365)),
                initialDateRange: DateTimeRange(
                  start: rangeFrom,
                  end: rangeTo,
                ),
              );
              if (range != null) {
                onRangeFromChanged(range.start);
                onRangeToChanged(range.end);
              }
            },
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: 'Date Range',
                suffixIcon: const Icon(Icons.calendar_today, size: 20),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
              child: Text(
                '${DateFormat('MMM d').format(rangeFrom)} - ${DateFormat('MMM d, y').format(rangeTo)}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGrid(BuildContext context, ColorScheme cs, bool isDark) {
    final days = rangeAvailability!.days;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
        childAspectRatio: 0.7,
      ),
      itemCount: days.length,
      itemBuilder: (context, index) {
        final day = days[index];
        return _DayCell(
          day: day,
          isWeekend: _isWeekend(day.date),
          dayOfWeek: _dayOfWeekShort(day.date),
          dayOfMonth: _dayOfMonth(day.date),
          isDark: isDark,
          colorScheme: cs,
          onTap: () => onJumpToDate(day.date),
        );
      },
    );
  }
}

class _DayCell extends StatelessWidget {
  final DateAvailabilitySummary day;
  final bool isWeekend;
  final String dayOfWeek;
  final int dayOfMonth;
  final bool isDark;
  final ColorScheme colorScheme;
  final VoidCallback onTap;

  const _DayCell({
    required this.day,
    required this.isWeekend,
    required this.dayOfWeek,
    required this.dayOfMonth,
    required this.isDark,
    required this.colorScheme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isFull = day.availableCount == 0 && day.totalSeats > 0;
    final hasAvailability = day.availableCount > 0;
    final fillPct =
        day.totalSeats > 0 ? (day.bookedCount / day.totalSeats) : 0.0;

    Color barColor;
    if (isFull) {
      barColor = Colors.red.shade400;
    } else if (hasAvailability) {
      barColor = Colors.green.shade500;
    } else {
      barColor = Colors.transparent;
    }

    Color bgColor;
    if (isFull) {
      bgColor = Colors.red.withValues(alpha: isDark ? 0.15 : 0.08);
    } else {
      bgColor = colorScheme.onSurface.withValues(alpha: 0.04);
    }

    return Tooltip(
      message: '${day.bookedCount} booked, ${day.availableCount} available',
      child: Material(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Opacity(
            opacity: isWeekend ? 0.45 : 1.0,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Day of week
                  Text(
                    dayOfWeek,
                    style: TextStyle(
                      fontSize: 9,
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  // Day number
                  Text(
                    '$dayOfMonth',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 3),
                  // Utilization bar
                  SizedBox(
                    height: 3,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: fillPct,
                        backgroundColor:
                            colorScheme.onSurface.withValues(alpha: 0.1),
                        valueColor: AlwaysStoppedAnimation(barColor),
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  // Count label
                  Text(
                    '${day.availableCount}/${day.totalSeats}',
                    style: TextStyle(
                      fontSize: 9,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
