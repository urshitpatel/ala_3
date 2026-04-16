import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const ExpenseTrackerApp());
}

/// ==========================================
/// DATA MODEL
/// ==========================================
class Expense {
  final String id;
  String title;
  double amount;
  DateTime date;

  Expense({
    required this.id,
    required this.title,
    required this.amount,
    required this.date,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'amount': amount,
        'date': date.toIso8601String(),
      };

  factory Expense.fromJson(Map<String, dynamic> json) => Expense(
        id: json['id'],
        title: json['title'],
        amount: json['amount'],
        date: DateTime.parse(json['date']),
      );
}

/// ==========================================
/// MAIN APP ROOT
/// ==========================================
class ExpenseTrackerApp extends StatelessWidget {
  const ExpenseTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Local Expense Tracker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.green,
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.grey[100],
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.green,
          foregroundColor: Colors.white,
          centerTitle: true,
        ),
      ),
      home: const ExpenseHomeScreen(),
    );
  }
}

/// ==========================================
/// EXPENSE TRACKER HOME SCREEN WITH CRUD LOGIC
/// ==========================================
class ExpenseHomeScreen extends StatefulWidget {
  const ExpenseHomeScreen({super.key});

  @override
  State<ExpenseHomeScreen> createState() => _ExpenseHomeScreenState();
}

class _ExpenseHomeScreenState extends State<ExpenseHomeScreen> {
  List<Expense> _expenses = [];
  final String _storageKey = 'local_expenses_data';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadExpenses(); // RETRIEVE DATA
  }

  /// 1. RETRIEVE DATA FROM SHAREDPREFERENCES
  Future<void> _loadExpenses() async {
    final prefs = await SharedPreferences.getInstance();
    final dataString = prefs.getString(_storageKey);

    if (dataString != null) {
      final List decodedList = jsonDecode(dataString);
      setState(() {
        _expenses = decodedList.map((e) => Expense.fromJson(e)).toList();
      });
    }
    setState(() {
      _isLoading = false;
    });
  }

  /// 2. STORE DATA TO SHAREDPREFERENCES
  Future<void> _saveExpenses() async {
    final prefs = await SharedPreferences.getInstance();
    final String encodedData =
        jsonEncode(_expenses.map((e) => e.toJson()).toList());
    await prefs.setString(_storageKey, encodedData);
  }

  /// 3. UPDATE / CREATE DIALOG
  void _showExpenseDialog({Expense? existingExpense, int? index}) {
    final titleController =
        TextEditingController(text: existingExpense?.title ?? '');
    final amountController = TextEditingController(
        text: existingExpense?.amount.toString() ?? '');

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            existingExpense == null ? 'Add New Expense' : 'Update Expense',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: InputDecoration(
                  labelText: 'Expense Name',
                  prefixIcon: const Icon(Icons.shopping_bag),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Amount (\$)',
                  prefixIcon: const Icon(Icons.attach_money),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                final String title = titleController.text.trim();
                final double? amount = double.tryParse(amountController.text.trim());

                if (title.isEmpty || amount == null || amount <= 0) return;

                setState(() {
                  if (existingExpense == null) {
                    // CREATE logic
                    _expenses.insert(
                      0,
                      Expense(
                        id: DateTime.now().millisecondsSinceEpoch.toString(),
                        title: title,
                        amount: amount,
                        date: DateTime.now(),
                      ),
                    );
                  } else {
                    // UPDATE logic
                    _expenses[index!] = Expense(
                      id: existingExpense.id,
                      title: title,
                      amount: amount,
                      date: existingExpense.date, // Keep original date
                    );
                  }
                });

                await _saveExpenses();
                if (context.mounted) Navigator.pop(context);
              },
              child: Text(existingExpense == null ? 'Save' : 'Update'),
            ),
          ],
        );
      },
    );
  }

  /// 4. DELETE DATA
  void _deleteExpense(int index) async {
    final deletedItem = _expenses[index];
    setState(() {
      _expenses.removeAt(index);
    });
    await _saveExpenses();

    if (mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${deletedItem.title} deleted.'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Calculate total expenses
    final double totalAmount = _expenses.fold(0, (sum, item) => sum + item.amount);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Local Expense Tracker', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Top Dashboard Card
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Colors.green, Colors.lightGreen],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.green.withOpacity(0.4),
                        blurRadius: 10,
                        offset: const Offset(0, 5),
                      )
                    ],
                  ),
                  child: Column(
                    children: [
                      const Text(
                        "Total Expenses",
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "\$${totalAmount.toStringAsFixed(2)}",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),

                // Expense List View (READ)
                Expanded(
                  child: _expenses.isEmpty
                      ? Center(
                          child: Text(
                            "No expenses yet.\nClick + to track a new expense.",
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey[600], fontSize: 16),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _expenses.length,
                          padding: const EdgeInsets.only(bottom: 80), // Padding for Floating Action Button
                          itemBuilder: (context, index) {
                            final expense = _expenses[index];
                            return Card(
                              elevation: 2,
                              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: Colors.green.withOpacity(0.1),
                                  child: const Icon(Icons.receipt_long, color: Colors.green),
                                ),
                                title: Text(
                                  expense.title,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                                ),
                                subtitle: Text(
                                  "${expense.date.day}/${expense.date.month}/${expense.date.year}",
                                  style: const TextStyle(color: Colors.grey),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      "-\$${expense.amount.toStringAsFixed(2)}",
                                      style: const TextStyle(
                                        color: Colors.redAccent,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    // UPDATE BUTTON
                                    IconButton(
                                      icon: const Icon(Icons.edit, color: Colors.blue),
                                      onPressed: () => _showExpenseDialog(
                                        existingExpense: expense,
                                        index: index,
                                      ),
                                    ),
                                    // DELETE BUTTON
                                    IconButton(
                                      icon: const Icon(Icons.delete, color: Colors.red),
                                      onPressed: () => _deleteExpense(index),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        onPressed: () => _showExpenseDialog(), // Open CREATE dialog
        icon: const Icon(Icons.add),
        label: const Text("Add Expense", style: TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }
}
