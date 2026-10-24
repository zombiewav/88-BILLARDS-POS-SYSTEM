import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_colors.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets/widgets.dart';
import '../../data/database.dart';
import '../../providers.dart';
import 'inventory_page.dart' show StockReasonLabel;

/// Every stock change, newest first: sales, stock in, adjustments, voids, free drinks.
class StockLogPage extends ConsumerWidget {
  const StockLogPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final moves = ref.watch(stockMovementsProvider).valueOrNull ?? const <StockMovement>[];
    final names = {
      for (final p in ref.watch(productsProvider).valueOrNull ?? const <Product>[]) p.id: p.name,
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.chevron_left),
                label: const Text('Inventory'),
              ),
              const SizedBox(width: 16),
              const PageTitle('Stock log', note: 'Every change, with before and after'),
            ],
          ),
          const SizedBox(height: 18),
          Expanded(
            child: AppCard(
              padding: EdgeInsets.zero,
              child: moves.isEmpty
                  ? Center(
                      child: Text('No stock changes yet.',
                          style: TextStyle(fontFamily: 'Barlow', fontSize: 16, color: c.muted)))
                  : ListView.separated(
                      itemCount: moves.length,
                      separatorBuilder: (_, _) => Divider(color: c.border, height: 1),
                      itemBuilder: (context, i) {
                        final m = moves[i];
                        final plus = m.delta > 0;
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 4),
                          title: Text(names[m.productId] ?? 'Product',
                              style: TextStyle(
                                  fontFamily: 'Barlow',
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                  color: c.text)),
                          subtitle: Text(
                            [
                              '${m.createdAt.month}/${m.createdAt.day} ${formatClock(m.createdAt)}',
                              m.reason.label,
                              '${m.stockBefore} → ${m.stockAfter}',
                              if (m.note != null) m.note!,
                            ].join(' · '),
                            style: TextStyle(fontFamily: 'Barlow', fontSize: 14, color: c.muted),
                          ),
                          trailing: Text(
                            '${plus ? '+' : ''}${m.delta}',
                            style: condensed(30, color: plus ? c.green : c.red),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
