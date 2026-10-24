import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_colors.dart';
import '../../core/format.dart';
import '../../core/product_image.dart';
import '../../core/theme.dart';
import '../../core/widgets/widgets.dart';
import '../../data/database.dart';
import '../../data/session_repository.dart';
import '../../providers.dart';
import '../session/pay_flow.dart' show PayCashDialog;

/// A table's open bill that the cart is being added to.
typedef SellTarget = ({String sessionId, String tableLabel});

/// Product grid and cart. Sells to a walk-in for cash, or adds benta to a
/// table's bill. Pass [attachTo] to open it already pointed at one table.
class SellPage extends ConsumerStatefulWidget {
  const SellPage({super.key, this.attachTo});

  final SellTarget? attachTo;

  @override
  ConsumerState<SellPage> createState() => _SellPageState();
}

class _SellPageState extends ConsumerState<SellPage> {
  final _cart = <String, int>{};
  final _search = TextEditingController();
  String _category = 'All';

  /// True: add to a table's bill. False: walk-in sale paid now.
  late bool _toTable = widget.attachTo != null;
  String? _tableSessionId;
  var _busy = false;

  @override
  void initState() {
    super.initState();
    _tableSessionId = widget.attachTo?.sessionId;
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _add(Product product) {
    final qty = _cart[product.id] ?? 0;
    if (qty >= product.stock) return;
    setState(() => _cart[product.id] = qty + 1);
  }

  void _remove(Product product) {
    final qty = _cart[product.id] ?? 0;
    setState(() {
      if (qty <= 1) {
        _cart.remove(product.id);
      } else {
        _cart[product.id] = qty - 1;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // A tab that is hidden does no work: no queries, no timers, no rebuilds.
    if (!TickerMode.valuesOf(context).enabled) return const SizedBox.shrink();
    final c = context.c;
    final all = ref.watch(productsProvider).valueOrNull ?? const <Product>[];
    final products = all.where((p) => p.active).toList();
    final byId = {for (final p in products) p.id: p};

    final categories = {
      for (final p in products)
        if (p.category.isNotEmpty) p.category,
    }.toList()
      ..sort();
    final query = _search.text.trim().toLowerCase();
    final shown = [
      for (final p in products)
        if ((_category == 'All' || p.category == _category) &&
            (query.isEmpty || p.name.toLowerCase().contains(query)))
          p,
    ];

    final cartLines = [
      for (final e in _cart.entries)
        if (byId[e.key] != null) (product: byId[e.key]!, qty: e.value),
    ];
    final total = cartLines.fold<int>(0, (sum, l) => sum + l.product.price * l.qty);

    final openTables = [
      for (final r in ref.watch(tablesProvider).valueOrNull ?? const <TableWithSession>[])
        if (r.session != null) r,
    ];
    final target = openTables.where((r) => r.session!.id == _tableSessionId).firstOrNull ??
        (widget.attachTo == null ? openTables.firstOrNull : null);
    final targetLabel = widget.attachTo?.tableLabel ?? target?.table.label;
    final targetSessionId = widget.attachTo?.sessionId ?? target?.session!.id;
    final toTable = _toTable && targetSessionId != null;

    final grid = shown.isEmpty
        ? Center(
            child: Text(
              products.isEmpty ? 'No products yet. Add some in Stock.' : 'No items match.',
              style: TextStyle(fontFamily: 'Barlow', fontSize: 16, color: c.muted),
            ),
          )
        : GridView.builder(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 230,
              mainAxisExtent: 330,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
            ),
            itemCount: shown.length,
            itemBuilder: (context, i) => _ProductTile(
              product: shown[i],
              inCart: _cart[shown[i].id] ?? 0,
              onTap: () => _add(shown[i]),
            ),
          );

    final cart = _CartPanel(
      targetLabel: targetLabel,
      toTable: toTable,
      canPickTable: openTables.length > 1 && widget.attachTo == null,
      hasTable: targetSessionId != null,
      lines: cartLines,
      total: total,
      busy: _busy,
      onAdd: _add,
      onRemove: _remove,
      onClear: () => setState(_cart.clear),
      onMode: (table) => setState(() => _toTable = table),
      onPickTable: () => _pickTable(openTables),
      onSubmit: () => _submit(toTable ? targetSessionId : null, total, targetLabel),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (widget.attachTo != null) ...[
                OutlinedButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.chevron_left),
                  label: Text(widget.attachTo!.tableLabel),
                ),
                const SizedBox(width: 16),
              ],
              const PageTitle('Sell items'),
              const SizedBox(width: 22),
              Expanded(
                child: Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    for (final cat in ['All', ...categories])
                      PillChip(
                        label: cat,
                        selected: _category == cat,
                        onTap: () => setState(() => _category = cat),
                      ),
                  ],
                ),
              ),
              SizedBox(
                width: 280,
                child: TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Search items',
                    prefixIcon: Icon(Icons.search, color: c.muted),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) {
                if (box.maxWidth >= 860) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: grid),
                      const SizedBox(width: 20),
                      SizedBox(width: 390, height: box.maxHeight, child: cart),
                    ],
                  );
                }
                return Column(
                  children: [
                    Expanded(child: grid),
                    const SizedBox(height: 14),
                    SizedBox(height: 380, child: cart),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickTable(List<TableWithSession> open) async {
    final c = context.c;
    final box = context.findRenderObject() as RenderBox;
    final picked = await showMenu<String>(
      context: context,
      color: c.card,
      position: RelativeRect.fromLTRB(box.size.width - 430, 220, 40, 0),
      items: [
        for (final r in open)
          PopupMenuItem(
            value: r.session!.id,
            child: Text('${r.table.label} · ${formatPeso(r.session!.total)}'),
          ),
      ],
    );
    if (picked != null) {
      setState(() {
        _tableSessionId = picked;
        _toTable = true;
      });
    }
  }

  Future<void> _submit(String? sessionId, int total, String? tableLabel) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final now = ref.read(clockProvider)();
    final repo = ref.read(saleRepositoryProvider);
    final cart = Map.of(_cart);

    setState(() => _busy = true);
    try {
      if (sessionId != null) {
        await repo.addToTable(sessionId: sessionId, cart: cart, now: now);
        messenger.showSnackBar(SnackBar(content: Text('Added to ${tableLabel ?? 'the table'}\'s bill')));
        if (widget.attachTo != null) {
          navigator.pop();
          return;
        }
      } else {
        final cash = await showDialog<int>(
          context: context,
          builder: (_) => PayCashDialog(title: 'Charge ${formatPeso(total)}', total: total),
        );
        if (cash == null) return;
        final change = await repo.sellStandalone(cart: cart, cashReceived: cash, now: now);
        messenger.showSnackBar(SnackBar(content: Text('Sold. Change ${formatPeso(change)}')));
      }
      if (mounted) setState(_cart.clear);
    } on StateError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } on ArgumentError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('${e.message}')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({required this.product, required this.inCart, required this.onTap});

  final Product product;
  final int inCart;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final out = product.stock <= 0;
    final low = isLowStock(product);
    final atLimit = inCart >= product.stock;
    final border = inCart > 0 ? c.gold : (low || out ? c.coral : c.border);

    final stockText = out
        ? 'Out of stock'
        : low
            ? 'Low: ${product.stock} left'
            : '${product.stock} in stock';

    return Opacity(
      opacity: out ? 0.55 : 1,
      child: Material(
        color: c.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: border, width: inCart > 0 || low ? 1.5 : 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: atLimit ? null : onTap,
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: ProductImage(path: product.imagePath)),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Text(product.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontFamily: 'Barlow',
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  color: c.text)),
                        ),
                        Text(formatPeso(product.price), style: condensed(28, color: c.gold)),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(stockText,
                        style: TextStyle(
                            fontFamily: 'Barlow',
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: low || out ? c.coral : c.green)),
                  ],
                ),
              ),
              if (inCart > 0)
                Positioned(
                  top: 16,
                  right: 16,
                  child: CircleAvatar(
                    radius: 15,
                    backgroundColor: c.gold,
                    child: Text('$inCart',
                        style: TextStyle(
                            fontFamily: 'Barlow',
                            fontWeight: FontWeight.w700,
                            color: c.onGold)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

typedef _CartLine = ({Product product, int qty});

class _CartPanel extends StatelessWidget {
  const _CartPanel({
    required this.targetLabel,
    required this.toTable,
    required this.canPickTable,
    required this.hasTable,
    required this.lines,
    required this.total,
    required this.busy,
    required this.onAdd,
    required this.onRemove,
    required this.onClear,
    required this.onMode,
    required this.onPickTable,
    required this.onSubmit,
  });

  final String? targetLabel;
  final bool toTable;
  final bool canPickTable;
  final bool hasTable;
  final List<_CartLine> lines;
  final int total;
  final bool busy;
  final ValueChanged<Product> onAdd;
  final ValueChanged<Product> onRemove;
  final VoidCallback onClear;
  final ValueChanged<bool> onMode;
  final VoidCallback onPickTable;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final c = context.c;

    Widget segment(String label, bool selected, VoidCallback? onTap) => Expanded(
          child: Material(
            color: selected ? c.selected : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: onTap,
              child: SizedBox(
                height: 44,
                child: Center(
                  child: Text(label,
                      style: TextStyle(
                          fontFamily: 'Barlow',
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: selected
                              ? c.gold
                              : (onTap == null ? c.muted.withValues(alpha: 0.5) : c.muted))),
                ),
              ),
            ),
          ),
        );

    final addLabel = toTable ? 'Add to $targetLabel bill' : 'Charge ${formatPeso(total)}';

    return AppCard(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Cart', style: condensed(30, color: c.text)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: c.isDark ? c.bg : c.raised,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: c.border),
            ),
            child: Row(
              children: [
                segment(
                  hasTable ? 'Charge to $targetLabel' : 'No open table',
                  toTable,
                  hasTable ? () => canPickTable && toTable ? onPickTable() : onMode(true) : null,
                ),
                segment('Walk-in', !toTable, () => onMode(false)),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: lines.isEmpty
                ? Center(
                    child: Text('Tap a product to add it',
                        style: TextStyle(fontFamily: 'Barlow', fontSize: 15, color: c.muted)))
                : ListView(
                    children: [
                      for (final l in lines)
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.border))),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(l.product.name,
                                    style: TextStyle(
                                        fontFamily: 'Barlow', fontSize: 17, color: c.text)),
                              ),
                              _StepButton(icon: Icons.remove, onTap: () => onRemove(l.product)),
                              SizedBox(
                                width: 44,
                                child: Center(
                                  child: Text('x${l.qty}',
                                      style: condensed(24, color: c.text)),
                                ),
                              ),
                              _StepButton(
                                  icon: Icons.add,
                                  onTap: l.qty >= l.product.stock ? null : () => onAdd(l.product)),
                              SizedBox(
                                width: 66,
                                child: Text(formatPeso(l.product.price * l.qty),
                                    textAlign: TextAlign.right,
                                    style: TextStyle(
                                        fontFamily: 'Barlow',
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: c.text)),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('Total', style: TextStyle(fontFamily: 'Barlow', fontSize: 16, color: c.muted)),
              const Spacer(),
              Text(formatPeso(total), style: condensed(60, color: c.text)),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: lines.isEmpty || busy || (toTable && !hasTable) ? null : onSubmit,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(58)),
            child: Text(addLabel),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: lines.isEmpty ? null : onClear,
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            child: const Text('Clear cart'),
          ),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Material(
      color: c.raised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: c.border),
      ),
      child: InkWell(
        customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        onTap: onTap,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, size: 20, color: onTap == null ? c.muted.withValues(alpha: 0.4) : c.text),
        ),
      ),
    );
  }
}
