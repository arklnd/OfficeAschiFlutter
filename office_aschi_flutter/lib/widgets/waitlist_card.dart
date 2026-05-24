import 'package:flutter/material.dart';
import '../models/models.dart';

/// Reusable waitlist card showing queued booking requests.
class WaitlistCard extends StatelessWidget {
  final List<WaitlistInfo> waitlist;

  const WaitlistCard({super.key, required this.waitlist});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                  backgroundColor: cs.secondaryContainer,
                  child: Text(
                    '${i + 1}',
                    style: TextStyle(color: cs.onSecondaryContainer),
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
}
