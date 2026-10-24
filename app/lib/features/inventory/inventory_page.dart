import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/app_colors.dart';
import '../../core/format.dart';
import '../../core/product_image.dart';
import '../../core/theme.dart';
import '../../core/widgets/widgets.dart';
import '../../data/database.dart';
import '../../domain/enums.dart';
import '../../providers.dart';
import 'stock_dialogs.dart';
import 'stock_log_page.dart';

const _types = ['Drinks', 'Snacks', 'Other'];

/// Stock: the product list with a side panel to add or edit a product.
class InventoryPage extends ConsumerStatefulWidget {
  const InventoryPage({super.key});

  @override
  ConsumerState<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends ConsumerState<InventoryPage> {
  String? _selectedId;

  final _name = TextEditingController();
  final _price = TextEditingController();
  final _cost = TextEditingController();
  final _stock = TextEditingController();
  final _low = TextEditingController(text: '5');
  var _type = _types.first;
  String? _imagePath;
  var _active = true;
  var _saving = false;

  @override
  void dispose() {
    for (final c in [_name, _price, _cost, _stock, _low]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Fills the side panel from [p], or clears it for a new product.
  void _load(Product? p) {
    _selectedId = p?.id;
    _name.text = p?.name ?? '';
    _price.text = p?.price.toString() ?? '';
    _cost.text = p?.costPrice?.toString() ?? '';
    _stock.text = p?.stock.toString() ?? '';
    _low.text = (p?.lowStockLevel ?? 5).toString();
    _type = p == null || p.category.isEmpty ? _types.first : p.category;
    _imagePath = p?.imagePath;
    _active = p?.active ?? true;
  }

  Product? _selected(List<Product> all) => all.where((p) => p.id == _selectedId).firstOrNull;

  bool get _valid => _name.text.trim().isNotEmpty && int.tryParse(_price.text) != null;

  Future<void> _pick(ImageSource source) async {
    try {
      final file = await ImagePicker().pickImage(source: source, maxWidth: 800, imageQuality: 85);
      if (file != null) setState(() => _imagePath = file.path);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Could not open the photo picker')));
      }
    }
  }

  Future<void> _save(List<Product> all) async {
    final repo = ref.read(productRepositoryProvider);
    final now = ref.read(clockProvider)();
    final messenger = ScaffoldMessenger.of(context);
    final existing = _selected(all);

    setState(() => _saving = true);
    try {
      var image = _imagePath;
      if (image != null && image != existing?.imagePath) image = await storeProductImage(image);

      final price = int.parse(_price.text);
      final cost = int.tryParse(_cost.text);
      final low = int.tryParse(_low.text) ?? 0;
      final stock = int.tryParse(_stock.text) ?? 0;

      if (existing == null) {
        await repo.createProduct(
          name: _name.text,
          category: _type,
          price: price,
          costPrice: cost,
          imagePath: image,
          openingStock: stock,
          lowStockLevel: low,
          now: now,
        );
        if (mounted) setState(() => _load(null));
        messenger.showSnackBar(const SnackBar(content: Text('Product added')));
      } else {
        await repo.updateProduct(
          id: existing.id,
          name: _name.text,
          category: _type,
          price: price,
          costPrice: cost,
          imagePath: image,
          lowStockLevel: low,
          active: _active,
          now: now,
        );
        // Changing the stock number is a count adjustment, so the stock log explains it.
        if (stock != existing.stock) {
          await repo.adjustToCount(
              productId: existing.id, counted: stock, note: 'Edited in Stock', now: now);
        }
        messenger.showSnackBar(const SnackBar(content: Text('Product saved')));
      }
    } on StateError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } on ArgumentError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('${e.message}')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _stockIn(List<Product> all) async {
    final p = _selected(all);
    if (p == null) return _needSelection();
    final r = await showDialog<StockInResult>(
      context: context,
      builder: (_) => StockInDialog(product: p),
    );
    if (r == null || !mounted) return;
    await _run(() => ref.read(productRepositoryProvider).stockIn(
          productId: p.id,
          qty: r.qty,
          note: r.note,
          now: ref.read(clockProvider)(),
        ));
    if (mounted) setState(() => _stock.text = '${p.stock + r.qty}');
  }

  Future<void> _adjust(List<Product> all) async {
    final p = _selected(all);
    if (p == null) return _needSelection();
    final r = await showDialog<AdjustResult>(
      context: context,
      builder: (_) => AdjustDialog(product: p),
    );
    if (r == null || !mounted) return;
    final repo = ref.read(productRepositoryProvider);
    final now = ref.read(clockProvider)();
    await _run(() => r.damaged
        ? repo.writeOff(productId: p.id, qty: r.value, note: r.note, now: now)
        : repo.adjustToCount(productId: p.id, counted: r.value, note: r.note, now: now));
    if (mounted) setState(() => _stock.text = '${r.damaged ? p.stock - r.value : r.value}');
  }

  void _needSelection() {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Tap a product in the list first')));
  }

  Future<void> _run(Future<void> Function() action) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
    } on StateError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } on ArgumentError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('${e.message}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    // A tab that is hidden does no work: no queries, no timers, no rebuilds.
    if (!TickerMode.valuesOf(context).enabled) return const SizedBox.shrink();
    final c = context.c;
    final all = ref.watch(productsProvider).valueOrNull ?? const <Product>[];
    final low = all.where((p) => p.active && isLowStock(p)).toList();
    final selected = _selected(all);

    final list = AppCard(
      padding: EdgeInsets.zero,
      child: all.isEmpty
          ? Center(
              child: Text('No products yet. Add one on the right.',
                  style: TextStyle(fontFamily: 'Barlow', fontSize: 16, color: c.muted)))
          : Column(
              children: [
                _HeaderRow(),
                Expanded(
                  child: ListView(
                    children: [
                      for (final p in all)
                        _ProductRow(
                          product: p,
                          selected: p.id == _selectedId,
                          onTap: () => setState(() => _load(p.id == _selectedId ? null : p)),
                        ),
                    ],
                  ),
                ),
              ],
            ),
    );

    final form = _FormPanel(
      editing: selected != null,
      name: _name,
      price: _price,
      cost: _cost,
      stock: _stock,
      low: _low,
      type: _type,
      imagePath: _imagePath,
      active: _active,
      saving: _saving,
      valid: _valid,
      onChanged: () => setState(() {}),
      onType: (t) => setState(() => _type = t),
      onActive: (v) => setState(() => _active = v),
      onPick: _pick,
      onClearImage: () => setState(() => _imagePath = null),
      onNew: () => setState(() => _load(null)),
      onSave: () => _save(all),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const PageTitle('Inventory'),
              const Spacer(),
              OutlinedButton(onPressed: () => _stockIn(all), child: const Text('Stock in')),
              const SizedBox(width: 12),
              OutlinedButton(onPressed: () => _adjust(all), child: const Text('Adjust')),
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: () => Navigator.of(context)
                    .push(MaterialPageRoute<void>(builder: (_) => const StockLogPage())),
                child: const Text('Log'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (low.isNotEmpty && ref.watch(lowStockWarningProvider)) ...[
            Banner2(
              icon: Icons.warning_amber_rounded,
              color: c.coral,
              text: '${low.length} ${low.length == 1 ? 'item is' : 'items are'} low on stock: '
                  '${low.map((p) => '${p.name} (${p.stock} left)').join(', ')}.',
            ),
            const SizedBox(height: 14),
          ],
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) {
                if (box.maxWidth >= 900) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: list),
                      const SizedBox(width: 22),
                      SizedBox(width: 390, height: box.maxHeight, child: form),
                    ],
                  );
                }
                return Column(
                  children: [
                    Expanded(child: list),
                    const SizedBox(height: 16),
                    SizedBox(height: 520, child: form),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final style = TextStyle(
        fontFamily: 'Barlow', fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: c.muted);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: c.isDark ? c.surface : c.raised.withValues(alpha: 0.5),
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 60),
          Expanded(flex: 5, child: Text('PRODUCT', style: style)),
          Expanded(flex: 3, child: Text('TYPE', style: style)),
          Expanded(flex: 2, child: Text('PRICE', textAlign: TextAlign.right, style: style)),
          Expanded(flex: 2, child: Text('STOCK', textAlign: TextAlign.right, style: style)),
          Expanded(flex: 3, child: Text('STATUS', textAlign: TextAlign.right, style: style)),
        ],
      ),
    );
  }
}

class _ProductRow extends StatelessWidget {
  const _ProductRow({required this.product, required this.selected, required this.onTap});

  final Product product;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final low = isLowStock(product);
    final tone = low ? c.coral : c.green;
    final body = TextStyle(fontFamily: 'Barlow', fontSize: 16, color: c.muted);

    return InkWell(
      onTap: onTap,
      child: Container(
        height: 62,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: selected ? c.selected.withValues(alpha: c.isDark ? 0.55 : 0.7) : null,
          border: Border(
            bottom: BorderSide(color: c.border),
            left: BorderSide(color: selected ? c.gold : Colors.transparent, width: 3),
          ),
        ),
        child: Opacity(
          opacity: product.active ? 1 : 0.5,
          child: Row(
            children: [
              ProductImage(path: product.imagePath, size: 40, radius: 8),
              const SizedBox(width: 20),
              Expanded(
                flex: 5,
                child: Text(product.name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontFamily: 'Barlow',
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: c.text)),
              ),
              Expanded(flex: 3, child: Text(product.category, style: body)),
              Expanded(
                  flex: 2,
                  child: Text(formatPeso(product.price), textAlign: TextAlign.right, style: body.copyWith(color: c.text))),
              Expanded(
                flex: 2,
                child: Text('${product.stock}',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                        fontFamily: 'Barlow', fontSize: 17, fontWeight: FontWeight.w700, color: tone)),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  !product.active ? 'Hidden' : (low ? 'Low stock' : 'OK'),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      fontFamily: 'Barlow',
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: product.active ? tone : c.muted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FormPanel extends StatelessWidget {
  const _FormPanel({
    required this.editing,
    required this.name,
    required this.price,
    required this.cost,
    required this.stock,
    required this.low,
    required this.type,
    required this.imagePath,
    required this.active,
    required this.saving,
    required this.valid,
    required this.onChanged,
    required this.onType,
    required this.onActive,
    required this.onPick,
    required this.onClearImage,
    required this.onNew,
    required this.onSave,
  });

  final bool editing;
  final TextEditingController name;
  final TextEditingController price;
  final TextEditingController cost;
  final TextEditingController stock;
  final TextEditingController low;
  final String type;
  final String? imagePath;
  final bool active;
  final bool saving;
  final bool valid;
  final VoidCallback onChanged;
  final ValueChanged<String> onType;
  final ValueChanged<bool> onActive;
  final ValueChanged<ImageSource> onPick;
  final VoidCallback onClearImage;
  final VoidCallback onNew;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final canUseCamera =
        defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;

    Widget label(String text) => Padding(
          padding: const EdgeInsets.only(bottom: 6, top: 14),
          child: Text(text, style: TextStyle(fontFamily: 'Barlow', fontSize: 13, color: c.muted)),
        );

    Widget number(TextEditingController controller, {String? prefix}) => TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(prefixText: prefix),
          onChanged: (_) => onChanged(),
        );

    final types = {..._types, type}.toList();

    return AppCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(editing ? 'Edit product' : 'Add product', style: condensed(32, color: c.text)),
              const Spacer(),
              if (editing) TextButton(onPressed: onNew, child: const Text('+ New')),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      _PhotoBox(path: imagePath),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          children: [
                            OutlinedButton.icon(
                              onPressed: canUseCamera ? () => onPick(ImageSource.camera) : null,
                              icon: const Icon(Icons.photo_camera_outlined, size: 20),
                              label: const Text('Take picture'),
                              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                            ),
                            const SizedBox(height: 8),
                            OutlinedButton.icon(
                              onPressed: () => onPick(ImageSource.gallery),
                              icon: const Icon(Icons.image_outlined, size: 20),
                              label: const Text('Insert image'),
                              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (imagePath != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(onPressed: onClearImage, child: const Text('Remove photo')),
                    ),
                  label('Product name'),
                  TextField(
                    controller: name,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(hintText: 'e.g. Sprite 290 ml'),
                    onChanged: (_) => onChanged(),
                  ),
                  label('Product type'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final t in types)
                        PillChip(label: t, selected: t == type, onTap: () => onType(t)),
                    ],
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [label('Price (per pc)'), number(price, prefix: '₱ ')],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [label('Stock on hand'), number(stock)],
                        ),
                      ),
                    ],
                  ),
                  label('Warn when stock is at or below'),
                  number(low),
                  label('Cost price (optional)'),
                  number(cost, prefix: '₱ '),
                  if (editing)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('Show in Sell',
                          style: TextStyle(fontFamily: 'Barlow', fontSize: 15, color: c.text)),
                      value: active,
                      onChanged: onActive,
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: valid && !saving ? onSave : null,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(58)),
            child: Text(editing ? 'Save product' : 'Add product'),
          ),
        ],
      ),
    );
  }
}

class _PhotoBox extends StatelessWidget {
  const _PhotoBox({required this.path});

  final String? path;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    if (path != null) return ProductImage(path: path, size: 100);
    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.muted.withValues(alpha: 0.5)),
      ),
      alignment: Alignment.center,
      child: Text('No photo', style: TextStyle(fontFamily: 'Barlow', fontSize: 13, color: c.muted)),
    );
  }
}

extension StockReasonLabel on StockReason {
  String get label => switch (this) {
        StockReason.sale => 'Sale',
        StockReason.stockIn => 'Stock in',
        StockReason.adjustment => 'Adjustment',
        StockReason.voidReturn => 'Void return',
        StockReason.damaged => 'Damaged / lost',
        StockReason.complimentary => 'Complimentary',
      };
}
