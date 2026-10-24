/// Pure billing math. Money is whole pesos (int), never double.
library;

class GameLine {
  const GameLine(this.qty, this.unitPrice);

  final int qty;
  final int unitPrice;

  int get amount => qty * unitPrice;
}

/// Mode 1: time block price plus every extension.
int timeTotal({required int blockPrice, Iterable<int> extensionAmounts = const []}) {
  return blockPrice + extensionAmounts.fold(0, (sum, a) => sum + a);
}

/// Mode 2: sum of games played times the price per game.
int gameTotal(Iterable<GameLine> lines) {
  return lines.fold(0, (sum, l) => sum + l.amount);
}

/// Race: the hall's income is the table fee only. Bet money is pass-through.
int raceTotal({required int tableFee}) => tableFee;

/// What the customer owes for the table: mode total plus benta.
int tableBill({required int modeTotal, int bentaTotal = 0}) => modeTotal + bentaTotal;

/// Change to hand back. Throws if the cash does not cover the total.
int changeDue({required int total, required int cashReceived}) {
  if (cashReceived < total) {
    throw ArgumentError('Cash received ($cashReceived) is less than the total ($total)');
  }
  return cashReceived - total;
}

/// One day of the notebook: Net = table income + benta - expenses - voids.
class DailyTotals {
  const DailyTotals({
    this.timeIncome = 0,
    this.gameIncome = 0,
    this.raceIncome = 0,
    this.benta = 0,
    this.expenses = 0,
    this.voids = 0,
  });

  final int timeIncome;
  final int gameIncome;
  final int raceIncome;
  final int benta;
  final int expenses;
  final int voids;

  int get billiard => timeIncome + gameIncome + raceIncome;
  int get billiardPlusBenta => billiard + benta;
  int get net => billiardPlusBenta - expenses - voids;
}
