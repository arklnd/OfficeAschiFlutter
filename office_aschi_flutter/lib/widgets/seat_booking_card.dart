import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../models/models.dart';

/// Reusable seat booking card used in team detail bookings tab.
///
/// Shows a seat's label, booking status, and either the booked person's
/// info or a "Book" button for available seats.
class SeatBookingCard extends StatelessWidget {
  final SeatView seat;
  final VoidCallback? onBook;
  final VoidCallback? onCancel;

  const SeatBookingCard({
    super.key,
    required this.seat,
    this.onBook,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final isBooked = seat.status == 'booked';
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isBooked ? cs.primary : AppColors.greenBorder(isDark),
          width: 1,
        ),
      ),
      color: isBooked ? cs.primaryContainer : AppColors.greenContainer(isDark),
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
                if (isBooked && onCancel != null)
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: onCancel,
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
                      style: TextStyle(color: cs.onPrimary, fontSize: 12),
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
                child: FilledButton.tonal(
                  onPressed: onBook,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.greenButtonBg(isDark),
                    foregroundColor: AppColors.greenButtonFg(isDark),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add, size: 16),
                      SizedBox(width: 4),
                      Text('Book'),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Reusable seat overview card used in the cross-team seat search screen.
///
/// Shows seat label, team name, engaged/vacant status, and engaged person info.
class SeatOverviewCard extends StatelessWidget {
  final SeatOverviewResponse seat;

  const SeatOverviewCard({super.key, required this.seat});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final engaged = seat.isEngaged;

    final bgColor = engaged
        ? (isDark ? cs.primaryContainer.withValues(alpha: 0.4) : cs.primaryContainer)
        : AppColors.greenContainer(isDark);
    final borderColor = engaged ? cs.primary : AppColors.greenBorder(isDark);

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
                        ? cs.error.withValues(alpha: 0.15)
                        : AppColors.greenTextLight.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    engaged ? 'Engaged' : 'Vacant',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: engaged
                          ? cs.error
                          : AppColors.greenBorderDark,
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
