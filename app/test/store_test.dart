import 'package:billiards_pos/data/database.dart';
import 'package:billiards_pos/data/product_repository.dart';
import 'package:billiards_pos/data/sale_repository.dart';
import 'package:billiards_pos/data/session_repository.dart';
import 'package:billiards_pos/domain/enums.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late ProductRepository products;
  late SaleRepository sales;
  late SessionRepository sessions;
  final t0 = DateTime(2026, 1, 1, 12);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.init();
    products = ProductRepository(db);
    sales = SaleRepository(db);
    sessions = SessionRepository(db);
  });

  tearDown(() => db.close());

  Future<Product> product(String name) =>
      (db.select(db.products)..where((p) => p.name.equals(name))).getSingle();

  Future<String> openTimeSession() async {
    final table = (await db.select(db.poolTables).get()).first;
    return sessions.startTimeSession(tableId: table.id, minutes: 30, price: 50, now: t0);
  }

  Future<Session> sessionOf(String id) async =>
      (await sessions.watchSession(id).first)!;

  group('benta on a table bill', () {
    test('adds to the bill, takes stock out and logs a sale movement', () async {
      final id = await openTimeSession();
      final coke = await product('Coke');

      await sales.addToTable(sessionId: id, cart: {coke.id: 2}, now: t0);

      expect((await sessionOf(id)).total, 50 + 2 * 15);
      expect((await product('Coke')).stock, 22);

      final move = (await db.select(db.stockMovements).get())
          .firstWhere((m) => m.reason == StockReason.sale);
      expect(move.delta, -2);
      expect(move.stockBefore, 24);
      expect(move.stockAfter, 22);
    });

    test('stays in the bill when time is extended afterwards', () async {
      final id = await openTimeSession();
      final coke = await product('Coke');
      await sales.addToTable(sessionId: id, cart: {coke.id: 1}, now: t0);

      await sessions.extend(sessionId: id, minutes: 60, amount: 100, now: t0);
      expect((await sessionOf(id)).total, 50 + 100 + 15);
    });

    test('is summed by product in the benta lines', () async {
      final id = await openTimeSession();
      final coke = await product('Coke');
      final royal = await product('Royal');
      await sales.addToTable(sessionId: id, cart: {coke.id: 1, royal.id: 1}, now: t0);
      await sales.addToTable(sessionId: id, cart: {coke.id: 2}, now: t0);

      final lines = await sales.watchSessionBenta(id).first;
      expect(lines.length, 2);
      expect(lines.firstWhere((l) => l.name == 'Coke').qty, 3);
    });

    test('is paid with the table, and works while waiting to pay', () async {
      final id = await openTimeSession();
      final coke = await product('Coke');
      await sessions.endTable(sessionId: id, now: t0);
      await sales.addToTable(sessionId: id, cart: {coke.id: 1}, now: t0);

      expect(await sessions.pay(sessionId: id, cashReceived: 100, now: t0), 35);
      expect((await db.select(db.payments).get()).single.amount, 65);
    });

    test('game bill keeps benta when a game is added', () async {
      final table = (await db.select(db.poolTables).get()).first;
      final id = await sessions.startGameSession(tableId: table.id, now: t0);
      final coke = await product('Coke');
      await sales.addToTable(sessionId: id, cart: {coke.id: 1}, now: t0);

      final ten = await (db.select(db.gameTypes)..where((g) => g.name.equals('10 balls')))
          .getSingle();
      await sessions.addGame(sessionId: id, gameTypeId: ten.id, now: t0);
      expect((await sessionOf(id)).total, 15 + 15);
    });

    test('not enough stock changes nothing', () async {
      final id = await openTimeSession();
      final coke = await product('Coke');
      final royal = await product('Royal');

      await expectLater(
        sales.addToTable(sessionId: id, cart: {royal.id: 1, coke.id: 25}, now: t0),
        throwsStateError,
      );
      expect((await sessionOf(id)).total, 50);
      expect((await product('Coke')).stock, 24);
      expect((await product('Royal')).stock, 24);
      expect(await db.select(db.sales).get(), isEmpty);
    });

    test('cannot add benta to a paid table', () async {
      final id = await openTimeSession();
      final coke = await product('Coke');
      await sessions.endTable(sessionId: id, now: t0);
      await sessions.pay(sessionId: id, cashReceived: 50, now: t0);

      expect(
        () => sales.addToTable(sessionId: id, cart: {coke.id: 1}, now: t0),
        throwsStateError,
      );
    });
  });

  group('walk-in sale', () {
    test('takes cash, gives change, records a payment on the sale', () async {
      final coke = await product('Coke');
      final change = await sales.sellStandalone(cart: {coke.id: 2}, cashReceived: 50, now: t0);

      expect(change, 20);
      final payment = (await db.select(db.payments).get()).single;
      expect(payment.saleId, isNotNull);
      expect(payment.sessionId, isNull);
      expect(payment.amount, 30);
      expect((await product('Coke')).stock, 22);
    });

    test('short cash rolls the whole sale back', () async {
      final coke = await product('Coke');
      await expectLater(
        sales.sellStandalone(cart: {coke.id: 2}, cashReceived: 10, now: t0),
        throwsArgumentError,
      );
      expect((await product('Coke')).stock, 24);
      expect(await db.select(db.sales).get(), isEmpty);
    });

    test('empty cart is rejected', () async {
      expect(
        () => sales.sellStandalone(cart: {}, cashReceived: 0, now: t0),
        throwsArgumentError,
      );
    });
  });

  group('products and inventory', () {
    test('a new product with opening stock gets a stock-in log row', () async {
      final id = await products.createProduct(
        name: ' Sting ',
        category: 'Drinks',
        price: 20,
        costPrice: 14,
        openingStock: 10,
        lowStockLevel: 3,
        now: t0,
      );
      final p = await product('Sting');
      expect(p.id, id);
      expect(p.stock, 10);

      final move = (await db.select(db.stockMovements).get())
          .firstWhere((m) => m.productId == id);
      expect(move.reason, StockReason.stockIn);
      expect(move.stockBefore, 0);
      expect(move.stockAfter, 10);
    });

    test('stock in, count adjustment and write-off each log a movement', () async {
      final coke = await product('Coke');

      await products.stockIn(productId: coke.id, qty: 6, note: 'Delivery', now: t0);
      expect((await product('Coke')).stock, 30);

      await products.adjustToCount(productId: coke.id, counted: 28, note: ' Recount ', now: t0);
      expect((await product('Coke')).stock, 28);

      await products.writeOff(productId: coke.id, qty: 3, note: 'Dropped', now: t0);
      expect((await product('Coke')).stock, 25);

      final moves = (await db.select(db.stockMovements).get())
          .where((m) => m.productId == coke.id && m.reason != StockReason.stockIn ||
              m.note == 'Delivery')
          .toList();
      expect(moves.map((m) => m.reason).toSet(),
          {StockReason.stockIn, StockReason.adjustment, StockReason.damaged});
      expect(moves.firstWhere((m) => m.reason == StockReason.adjustment).note, 'Recount');
      expect(moves.firstWhere((m) => m.reason == StockReason.adjustment).delta, -2);
    });

    test('an unchanged count writes nothing', () async {
      final coke = await product('Coke');
      final before = (await db.select(db.stockMovements).get()).length;
      await products.adjustToCount(productId: coke.id, counted: 24, now: t0);
      expect((await db.select(db.stockMovements).get()).length, before);
    });

    test('cannot write off more than is in stock', () async {
      final coke = await product('Coke');
      await expectLater(
        products.writeOff(productId: coke.id, qty: 99, now: t0),
        throwsStateError,
      );
      expect((await product('Coke')).stock, 24);
    });

    test('editing a product leaves its stock alone; hidden products cannot be sold', () async {
      final coke = await product('Coke');
      await products.updateProduct(
        id: coke.id,
        name: 'Coca-Cola',
        category: 'Drinks',
        price: 18,
        costPrice: 11,
        lowStockLevel: 8,
        active: false,
        now: t0,
      );
      final edited = await product('Coca-Cola');
      expect(edited.price, 18);
      expect(edited.stock, 24);

      await expectLater(
        sales.sellStandalone(cart: {coke.id: 1}, cashReceived: 20, now: t0),
        throwsStateError,
      );
    });

    test('validation rejects blank names and negative prices', () async {
      expect(
        () => products.createProduct(name: '  ', category: '', price: 10, now: t0),
        throwsArgumentError,
      );
      expect(
        () => products.createProduct(name: 'X', category: '', price: -1, now: t0),
        throwsArgumentError,
      );
    });
  });
}
