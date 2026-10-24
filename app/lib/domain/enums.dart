/// How a table session is played and billed.
enum PlayMode { time, game, race }

/// Lifecycle of a session: play first, End table, then Pay.
enum SessionStatus { running, waitingToPay, paid, unpaid }

/// What the Tables dashboard shows for a table (derived, never stored).
enum TableStatus { free, playing, endingSoon, waitingToPay }

enum StockReason { sale, stockIn, adjustment, voidReturn, damaged, complimentary }

enum ExpenseSource { manual, complimentary }

/// Owner: everything, approves voids, edits prices and the map. Cashier: tables, sell, expenses.
enum StaffRole { owner, cashier }
