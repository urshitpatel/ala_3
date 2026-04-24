import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NoteAPP());
}

/// --- ENUMS & CONSTANTS ---
enum SortOption { Date, Priority, Category, Status }

enum TaskSection { All, Today, Upcoming, Completed }

const List<String> kCategories = [
  'Work',
  'Study',
  'Personal',
  'Health',
  'Finance',
];
const List<String> kPriorities = ['High', 'Medium', 'Low'];

Color getPriorityColor(String p) {
  if (p == 'High') return const Color(0xFFFF4C60);
  if (p == 'Medium') return const Color(0xFFFFB236);
  return const Color(0xFF00E396);
}

int getPriorityWeight(String p) {
  if (p == 'High') return 3;
  if (p == 'Medium') return 2;
  return 1;
}

bool isToday(DateTime date) {
  final now = DateTime.now();
  return date.year == now.year &&
      date.month == now.month &&
      date.day == now.day;
}

bool isUpcoming(DateTime date) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final taskDate = DateTime(date.year, date.month, date.day);
  return taskDate.isAfter(today);
}

/// --- MODELS ---
class Task {
  final String id;
  String title;
  String description;
  String category;
  DateTime date;
  String priority;
  bool isCompleted;

  Task({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.date,
    required this.priority,
    this.isCompleted = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'category': category,
    'date': date.toIso8601String(),
    'priority': priority,
    'isCompleted': isCompleted,
  };

  factory Task.fromJson(Map<String, dynamic> json) => Task(
    id: json['id'],
    title: json['title'],
    description: json['description'] ?? '',
    category: json['category'] ?? kCategories.first,
    date: json['date'] != null ? DateTime.parse(json['date']) : DateTime.now(),
    priority: json['priority'] ?? 'Medium',
    isCompleted: json['isCompleted'] ?? false,
  );
}

/// --- APP ROOT ---
class NoteAPP extends StatefulWidget {
  const NoteAPP({super.key});

  @override
  State<NoteAPP> createState() => _NoteAppState();
}

class _NoteAppState extends State<NoteAPP> {
  ThemeMode _themeMode = ThemeMode.system;

  void toggleTheme() {
    HapticFeedback.lightImpact();
    setState(() {
      _themeMode = _themeMode == ThemeMode.light
          ? ThemeMode.dark
          : ThemeMode.light;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Note Tasks',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      home: HomeScreen(onThemeToggle: toggleTheme),
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: Colors.transparent,
      fontFamily: 'Inter',
      appBarTheme: const AppBarTheme(
        elevation: 0,
        backgroundColor: Colors.transparent,
        centerTitle: true,
      ),
    );
  }
}

/// --- REUSABLE GLASSMORPHISM WIDGET ---
class GlassPanel extends StatelessWidget {
  final Widget child;
  final double blur;
  final double opacity;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final BoxBorder? border;
  final Color? colorHint;
  final bool isNeon;

  const GlassPanel({
    super.key,
    required this.child,
    this.blur = 20.0,
    this.opacity = 0.15,
    this.borderRadius,
    this.padding,
    this.margin,
    this.border,
    this.colorHint,
    this.isNeon = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final rRadius = borderRadius ?? BorderRadius.circular(24);
    final baseColor =
        colorHint ?? (isDark ? const Color(0xFF0F172A) : Colors.white);

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: rRadius,
        boxShadow: isNeon && isDark && colorHint != null
            ? [
                BoxShadow(
                  color: colorHint!.withOpacity(0.5),
                  blurRadius: 30,
                  spreadRadius: -4,
                  offset: const Offset(0, 8),
                ),
              ]
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(isDark ? 0.5 : 0.05),
                  blurRadius: 30,
                  offset: const Offset(0, 15),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: rRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            padding: padding,
            decoration: BoxDecoration(
              color: baseColor.withOpacity(opacity),
              borderRadius: rRadius,
              border:
                  border ??
                  Border.all(
                    color: Colors.white.withOpacity(isDark ? 0.08 : 0.6),
                    width: isDark ? 1.0 : 1.5,
                  ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// --- HOME SCREEN ---
class HomeScreen extends StatefulWidget {
  final VoidCallback onThemeToggle;
  const HomeScreen({super.key, required this.onThemeToggle});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  List<Task> _tasks = [];
  bool _isLoading = true;
  final String _storageKey = 'note_tasks_v3';
  List<String> _categories = List.from(kCategories);

  String _searchQuery = '';
  SortOption _sortOption = SortOption.Date;
  TaskSection _activeSection = TaskSection.All;

  late AnimationController _animController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeIn,
    );
    _loadTasks();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _triggerCascade() {
    _animController.forward(from: 0.0);
  }

  // --- LOCAL STORAGE LOGIC ---
  Future<void> _loadTasks() async {
    final prefs = await SharedPreferences.getInstance();
    final dataString = prefs.getString(_storageKey);

    if (dataString != null) {
      final List decodedList = jsonDecode(dataString);
      setState(() {
        _tasks = decodedList.map((e) => Task.fromJson(e)).toList();
      });
    }
    final catsRaw = prefs.getStringList('${_storageKey}_categories');
    if (catsRaw != null && catsRaw.isNotEmpty) {
      setState(() => _categories = catsRaw);
    }
    setState(() => _isLoading = false);
    _triggerCascade();
  }

  Future<void> _saveTasks() async {
    final prefs = await SharedPreferences.getInstance();
    final String encodedData = jsonEncode(
      _tasks.map((e) => e.toJson()).toList(),
    );
    await prefs.setString(_storageKey, encodedData);
    await prefs.setStringList('${_storageKey}_categories', _categories);
  }

  // --- GETTERS & LOGIC ---
  List<Task> get filteredTasks {
    var list = _tasks.where((t) {
      if (_searchQuery.isNotEmpty) {
        if (!t.title.toLowerCase().contains(_searchQuery.toLowerCase()) &&
            !t.description.toLowerCase().contains(_searchQuery.toLowerCase())) {
          return false;
        }
      }
      if (_activeSection == TaskSection.Completed) return t.isCompleted;
      if (_activeSection == TaskSection.Today)
        return isToday(t.date) && !t.isCompleted;
      if (_activeSection == TaskSection.Upcoming)
        return isUpcoming(t.date) && !t.isCompleted;
      return true;
    }).toList();

    list.sort((a, b) {
      if (_sortOption == SortOption.Date) return a.date.compareTo(b.date);
      if (_sortOption == SortOption.Priority)
        return getPriorityWeight(
          b.priority,
        ).compareTo(getPriorityWeight(a.priority));
      if (_sortOption == SortOption.Category)
        return a.category.compareTo(b.category);
      return a.isCompleted == b.isCompleted ? 0 : (a.isCompleted ? 1 : -1);
    });

    return list;
  }

  void _showTaskDialog({Task? existingTask}) {
    final titleController = TextEditingController(
      text: existingTask?.title ?? '',
    );
    final descController = TextEditingController(
      text: existingTask?.description ?? '',
    );
    String selectedCategory = existingTask?.category ?? _categories.first;
    if (!_categories.contains(selectedCategory)) {
        selectedCategory = _categories.first;
    }
    String selectedPriority = existingTask?.priority ?? 'Medium';
    DateTime selectedDate = existingTask?.date ?? DateTime.now();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            return GlassPanel(
              blur: 35,
              opacity: isDark ? 0.3 : 0.85,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(40),
              ),
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                left: 24,
                right: 24,
                top: 24,
              ),
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 50,
                        height: 5,
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white30 : Colors.black26,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 30),
                    Text(
                      existingTask == null ? 'New Mission' : 'Update Mission',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                        letterSpacing: 0.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 30),

                    // Inputs
                    _buildInputField(
                      controller: titleController,
                      label: 'Title',
                      icon: Icons.title_rounded,
                      isDark: isDark,
                    ),
                    const SizedBox(height: 16),
                    _buildInputField(
                      controller: descController,
                      label: 'Description',
                      icon: Icons.map_rounded,
                      isDark: isDark,
                      maxLines: 2,
                    ),
                    const SizedBox(height: 20),

                    // Fields Row 1 (Date & Category)
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () async {
                              HapticFeedback.lightImpact();
                              DateTime? picked = await showDatePicker(
                                context: context,
                                initialDate: selectedDate,
                                firstDate: DateTime(2000),
                                lastDate: DateTime(2100),
                                builder: (context, child) => Theme(
                                  data: Theme.of(context).copyWith(
                                    colorScheme: isDark
                                        ? const ColorScheme.dark(
                                            primary: Color(0xFF00FFC2),
                                          )
                                        : const ColorScheme.light(
                                            primary: Color(0xFF6C63FF),
                                          ),
                                  ),
                                  child: child!,
                                ),
                              );
                              if (picked != null)
                                setModalState(() => selectedDate = picked);
                            },
                            child: GlassPanel(
                              blur: 10,
                              opacity: isDark ? 0.1 : 0.5,
                              borderRadius: BorderRadius.circular(20),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 16,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.calendar_month_rounded,
                                    color: isDark
                                        ? Colors.white70
                                        : Colors.black54,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    '${selectedDate.day}/${selectedDate.month}/${selectedDate.year}',
                                    style: TextStyle(
                                      color: isDark
                                          ? Colors.white
                                          : Colors.black87,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: GlassPanel(
                            blur: 10,
                            opacity: isDark ? 0.1 : 0.5,
                            borderRadius: BorderRadius.circular(20),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: selectedCategory,
                                dropdownColor: isDark
                                    ? const Color(0xFF1E293B)
                                    : Colors.white,
                                isExpanded: true,
                                icon: Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  color: isDark
                                      ? Colors.white54
                                      : Colors.black54,
                                ),
                                style: TextStyle(
                                  color: isDark ? Colors.white : Colors.black87,
                                  fontWeight: FontWeight.w600,
                                  fontFamily: 'Inter',
                                ),
                                items: [
                                  ..._categories.map(
                                    (c) => DropdownMenuItem(
                                      value: c,
                                      child: Text(c),
                                    ),
                                  ),
                                  const DropdownMenuItem(
                                    value: '__MANAGE__',
                                    child: Text('+ Manage Categories...', style: TextStyle(color: Colors.blueAccent)),
                                  )
                                ],
                                onChanged: (val) async {
                                  HapticFeedback.selectionClick();
                                  if (val == '__MANAGE__') {
                                    await _showManageCategoriesDialog();
                                    setModalState(() {
                                      if (!_categories.contains(selectedCategory)) {
                                        selectedCategory = _categories.first;
                                      }
                                    });
                                  } else {
                                    setModalState(() => selectedCategory = val!);
                                  }
                                },
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Priority Selector
                    Text(
                      'Priority Level',
                      style: TextStyle(
                        color: isDark ? Colors.white54 : Colors.black54,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: kPriorities.map((p) {
                        bool sel = p == selectedPriority;
                        return Expanded(
                          child: GestureDetector(
                            onTap: () {
                              HapticFeedback.lightImpact();
                              setModalState(() => selectedPriority = p);
                            },
                            child: GlassPanel(
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              blur: sel ? 20 : 5,
                              opacity: sel ? 0.9 : (isDark ? 0.1 : 0.4),
                              colorHint: sel ? getPriorityColor(p) : null,
                              isNeon: sel,
                              borderRadius: BorderRadius.circular(16),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              child: Center(
                                child: Text(
                                  p,
                                  style: TextStyle(
                                    color: sel
                                        ? (isDark ? Colors.black : Colors.white)
                                        : (isDark
                                              ? Colors.white54
                                              : Colors.black87),
                                    fontWeight: FontWeight.w900,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 40),

                    // Action Button
                    GestureDetector(
                      onTap: () async {
                        HapticFeedback.mediumImpact();
                        final title = titleController.text.trim();
                        final desc = descController.text.trim();

                        if (title.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text(
                                'Mission missing title!',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                              behavior: SnackBarBehavior.floating,
                              backgroundColor: const Color(0xFFFF4C60),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                          );
                          return;
                        }

                        setState(() {
                          if (existingTask == null) {
                            _tasks.insert(
                              0,
                              Task(
                                id: DateTime.now().millisecondsSinceEpoch
                                    .toString(),
                                title: title,
                                description: desc,
                                category: selectedCategory,
                                date: selectedDate,
                                priority: selectedPriority,
                              ),
                            );
                          } else {
                            existingTask.title = title;
                            existingTask.description = desc;
                            existingTask.category = selectedCategory;
                            existingTask.date = selectedDate;
                            existingTask.priority = selectedPriority;
                          }
                        });

                        await _saveTasks();
                        _triggerCascade(); // Animate new layout
                        if (context.mounted) Navigator.pop(context);
                      },
                      child: GlassPanel(
                        blur: 30,
                        opacity: 0.9,
                        colorHint: isDark
                            ? const Color(0xFF00FFC2)
                            : const Color(0xFF6C63FF),
                        isNeon: true,
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        borderRadius: BorderRadius.circular(20),
                        child: Center(
                          child: Text(
                            existingTask == null
                                ? 'Engage Mission'
                                : 'Update Data',
                            style: TextStyle(
                              color: isDark
                                  ? const Color(0xFF0F172A)
                                  : Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showManageCategoriesDialog() async {
    final textController = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            return Dialog(
              backgroundColor: Colors.transparent,
              elevation: 0,
              insetPadding: const EdgeInsets.all(24),
              child: GlassPanel(
                blur: 35,
                opacity: isDark ? 0.3 : 0.85,
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Manage Categories',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 20),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 300),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: _categories.length,
                        physics: const BouncingScrollPhysics(),
                        itemBuilder: (ctx, i) {
                          final cat = _categories[i];
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(cat, style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontWeight: FontWeight.w600)),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                              onPressed: () {
                                if (_categories.length > 1) {
                                  setDialogState(() {
                                    _categories.removeAt(i);
                                  });
                                  setState(() {});
                                  _saveTasks();
                                }
                              },
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: GlassPanel(
                            blur: 10,
                            opacity: isDark ? 0.1 : 0.5,
                            borderRadius: BorderRadius.circular(16),
                            child: TextField(
                              controller: textController,
                              style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.w600),
                              decoration: InputDecoration(
                                hintText: 'New Category...',
                                hintStyle: TextStyle(color: isDark ? Colors.white54 : Colors.black54),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () {
                            HapticFeedback.mediumImpact();
                            final val = textController.text.trim();
                            if (val.isNotEmpty && !_categories.contains(val)) {
                              setDialogState(() {
                                _categories.add(val);
                                textController.clear();
                              });
                              setState(() {});
                              _saveTasks();
                            }
                          },
                          child: GlassPanel(
                            blur: 10,
                            opacity: 0.9,
                            colorHint: isDark ? const Color(0xFF00FFC2) : const Color(0xFF6C63FF),
                            borderRadius: BorderRadius.circular(16),
                            padding: const EdgeInsets.all(12),
                            child: const Icon(Icons.add_rounded, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required bool isDark,
    int maxLines = 1,
  }) {
    return GlassPanel(
      blur: 10,
      opacity: isDark ? 0.1 : 0.5,
      borderRadius: BorderRadius.circular(20),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        style: TextStyle(
          color: isDark ? Colors.white : Colors.black87,
          fontWeight: FontWeight.w600,
        ),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(
            color: isDark ? Colors.white54 : Colors.black54,
          ),
          prefixIcon: Icon(
            icon,
            color: isDark ? Colors.white70 : Colors.black54,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 20,
          ),
        ),
      ),
    );
  }

  void _deleteTask(String id) async {
    final index = _tasks.indexWhere((t) => t.id == id);
    if (index >= 0) {
      final removed = _tasks.removeAt(index);
      setState(() {});
      await _saveTasks();
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Erased "${removed.title}"',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFF1E293B),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            action: SnackBarAction(
              label: 'UNDO',
              textColor: const Color(0xFF00FFC2),
              onPressed: () {
                setState(() => _tasks.insert(index, removed));
                _triggerCascade();
                _saveTasks();
              },
            ),
          ),
        );
      }
    }
  }

  void _toggleComplete(String id) async {
    HapticFeedback.heavyImpact();
    final index = _tasks.indexWhere((t) => t.id == id);
    if (index >= 0) {
      setState(() => _tasks[index].isCompleted = !_tasks[index].isCompleted);
      await _saveTasks();
    }
  }

  // --- UI BUILDING ---
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fTasks = filteredTasks;

    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF020617)
            : const Color(0xFFF1F5F9), // Deep Slate vs Clean White
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          clipBehavior: Clip.none,
          children: [
            // Cyberpunk Neon Orbs
            Positioned(
              top: -150,
              left: -150,
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 120, sigmaY: 120),
                child: Container(
                  width: 500,
                  height: 500,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color:
                        (isDark
                                ? const Color(0xFF8B5CF6)
                                : const Color(0xFFC7D2FE))
                            .withOpacity(isDark ? 0.25 : 0.5),
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: -150,
              right: -150,
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 120, sigmaY: 120),
                child: Container(
                  width: 500,
                  height: 500,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color:
                        (isDark
                                ? const Color(0xFF00FFC2)
                                : const Color(0xFFFBCFE8))
                            .withOpacity(isDark ? 0.15 : 0.5),
                  ),
                ),
              ),
            ),

            // Scrollable Content
            SafeArea(
              bottom: false,
              child: Column(
                children: [
                  _buildAppBar(isDark),
                  _buildDashboardStats(isDark),
                  _buildSearchBar(isDark),
                  _buildSections(isDark),
                  Expanded(
                    child: _isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : FadeTransition(
                            opacity: _fadeAnimation,
                            child: fTasks.isEmpty
                                ? _buildEmptyState(isDark)
                                : _buildResponsiveTaskList(fTasks),
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
        floatingActionButton: _buildAnimatedFAB(isDark),
      ),
    );
  }

  Widget _buildAppBar(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(
                Icons.blur_on_rounded,
                size: 32,
                color: isDark
                    ? const Color(0xFF00FFC2)
                    : const Color(0xFF6C63FF),
              ),
              const SizedBox(width: 12),
              Text(
                'Note',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
            ],
          ),
          GlassPanel(
            blur: 15,
            opacity: isDark ? 0.2 : 0.5,
            borderRadius: BorderRadius.circular(16),
            child: IconButton(
              onPressed: widget.onThemeToggle,
              icon: Icon(
                isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                color: isDark
                    ? const Color(0xFFFFB236)
                    : const Color(0xFF0F172A),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardStats(bool isDark) {
    final total = _tasks.length;
    final completed = _tasks.where((t) => t.isCompleted).length;
    final pending = total - completed;
    final progress = total == 0 ? 0.0 : completed / total;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: GlassPanel(
        blur: 35,
        opacity: isDark ? 0.4 : 0.8,
        colorHint: isDark ? const Color(0xFF1E1B4B) : const Color(0xFF6C63FF),
        padding: const EdgeInsets.all(28),
        borderRadius: BorderRadius.circular(36),
        isNeon: true,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'OVERVIEW',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _buildStatCol(
                        'Total',
                        '$total',
                        isDark ? const Color(0xFF00FFC2) : Colors.white,
                      ),
                      _buildStatCol(
                        'Done',
                        '$completed',
                        isDark
                            ? const Color(0xFF8B5CF6)
                            : const Color(0xFF00FFC2),
                      ),
                      _buildStatCol(
                        'Left',
                        '$pending',
                        const Color(0xFFFFB236),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: progress),
              duration: const Duration(milliseconds: 1400),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) {
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 80,
                      height: 80,
                      child: CircularProgressIndicator(
                        value: value,
                        strokeWidth: 10,
                        strokeCap: StrokeCap.round,
                        color: isDark ? const Color(0xFF00FFC2) : Colors.white,
                        backgroundColor: Colors.white.withOpacity(0.1),
                      ),
                    ),
                    Text(
                      '${(value * 100).toInt()}%',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCol(String label, String val, Color c) {
    return Padding(
      padding: const EdgeInsets.only(right: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            val,
            style: TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w900,
              height: 1.1,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              color: c,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: GlassPanel(
        blur: 15,
        opacity: isDark ? 0.1 : 0.6,
        borderRadius: BorderRadius.circular(24),
        child: TextField(
          onChanged: (val) {
            setState(() => _searchQuery = val);
            _triggerCascade();
          },
          style: TextStyle(
            color: isDark ? Colors.white : const Color(0xFF0F172A),
            fontWeight: FontWeight.w600,
          ),
          decoration: InputDecoration(
            hintText: 'Search matrix...',
            hintStyle: TextStyle(
              color: isDark ? Colors.white30 : Colors.black38,
            ),
            prefixIcon: Icon(
              Icons.search_rounded,
              color: isDark ? Colors.white54 : Colors.black54,
            ),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 18),
            suffixIcon: PopupMenuButton<SortOption>(
              icon: Icon(
                Icons.tune_rounded,
                color: isDark ? Colors.white70 : const Color(0xFF6C63FF),
              ),
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              onSelected: (val) {
                HapticFeedback.selectionClick();
                setState(() => _sortOption = val);
                _triggerCascade();
              },
              itemBuilder: (context) => SortOption.values
                  .map(
                    (s) => PopupMenuItem(
                      value: s,
                      child: Text(
                        'Sort by ${s.name}',
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSections(bool isDark) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: TaskSection.values.map((section) {
          final isSelected = _activeSection == section;
          return GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              setState(() => _activeSection = section);
              _triggerCascade();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: GlassPanel(
                blur: isSelected ? 20 : 10,
                opacity: isSelected ? 0.9 : (isDark ? 0.1 : 0.5),
                colorHint: isSelected
                    ? (isDark
                          ? const Color(0xFF00FFC2)
                          : const Color(0xFF6C63FF))
                    : null,
                isNeon: isSelected,
                borderRadius: BorderRadius.circular(20),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 14,
                ),
                child: Text(
                  section.name,
                  style: TextStyle(
                    color: isSelected
                        ? (isDark ? const Color(0xFF0F172A) : Colors.white)
                        : (isDark ? Colors.white70 : Colors.black87),
                    fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 1200),
        curve: Curves.elasticOut,
        builder: (context, value, child) {
          return Transform.scale(scale: value, child: child);
        },
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                  child: Icon(
                    Icons.done_all_rounded,
                    size: 100,
                    color:
                        (isDark
                                ? const Color(0xFF8B5CF6)
                                : const Color(0xFF6C63FF))
                            .withOpacity(0.5),
                  ),
                ),
                GlassPanel(
                  blur: 20,
                  opacity: isDark ? 0.1 : 0.5,
                  borderRadius: BorderRadius.circular(50),
                  padding: const EdgeInsets.all(40),
                  child: Icon(
                    Icons.done_all_rounded,
                    size: 80,
                    color: isDark ? Colors.white : const Color(0xFF6C63FF),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 40),
            Text(
              'Space Clear',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'You hold no current objectives.',
              style: TextStyle(
                fontSize: 16,
                color: isDark ? Colors.white54 : Colors.black54,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResponsiveTaskList(List<Task> fTasks) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth > 700) {
          return GridView.builder(
            padding: const EdgeInsets.only(
              left: 24,
              right: 24,
              bottom: 120,
              top: 12,
            ),
            physics: const BouncingScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 20,
              mainAxisSpacing: 20,
              childAspectRatio: 1.8,
            ),
            itemCount: fTasks.length,
            itemBuilder: (context, index) =>
                _buildAnimatedTaskCard(fTasks[index], index),
          );
        } else {
          return ListView.builder(
            padding: const EdgeInsets.only(
              left: 24,
              right: 24,
              bottom: 120,
              top: 12,
            ),
            physics: const BouncingScrollPhysics(),
            itemCount: fTasks.length,
            itemBuilder: (context, index) => Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: _buildAnimatedTaskCard(fTasks[index], index),
            ),
          );
        }
      },
    );
  }

  Widget _buildAnimatedTaskCard(Task task, int index) {
    final animation = CurvedAnimation(
      parent: _animController,
      curve: Interval(
        (index * 0.08).clamp(0.0, 1.0),
        1.0,
        curve: Curves.easeOutQuart,
      ),
    );

    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.4),
          end: Offset.zero,
        ).animate(animation),
        child: _buildTaskCard(task),
      ),
    );
  }

  Widget _buildTaskCard(Task task) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pColor = getPriorityColor(task.priority);

    return Dismissible(
      key: Key(task.id),
      confirmDismiss: (dir) async {
        if (dir == DismissDirection.startToEnd) {
          _toggleComplete(task.id);
          return false; // Prevent dismiss on complete swipe
        }
        HapticFeedback.heavyImpact();
        return true;
      },
      onDismissed: (_) => _deleteTask(task.id),
      background: GlassPanel(
        blur: 15,
        opacity: 0.9,
        colorHint: const Color(0xFF00E396),
        borderRadius: BorderRadius.circular(32),
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: const Align(
          alignment: Alignment.centerLeft,
          child: Icon(
            Icons.check_circle_rounded,
            color: Colors.white,
            size: 40,
          ),
        ),
      ),
      secondaryBackground: GlassPanel(
        blur: 15,
        opacity: 0.9,
        colorHint: const Color(0xFFFF4C60),
        borderRadius: BorderRadius.circular(32),
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: const Align(
          alignment: Alignment.centerRight,
          child: Icon(
            Icons.delete_sweep_rounded,
            color: Colors.white,
            size: 40,
          ),
        ),
      ),
      child: GlassPanel(
        blur: 25,
        opacity: isDark ? 0.15 : 0.65,
        colorHint: task.isCompleted
            ? const Color(0xFF00E396).withOpacity(isDark ? 0.05 : 0.15)
            : null,
        borderRadius: BorderRadius.circular(32),
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: pColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: pColor,
                          boxShadow: [
                            BoxShadow(
                              color: pColor.withOpacity(0.5),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        task.priority.toUpperCase(),
                        style: TextStyle(
                          color: pColor,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    _showTaskDialog(existingTask: task);
                  },
                  child: Icon(
                    Icons.edit_note_rounded,
                    color: isDark ? Colors.white54 : Colors.black54,
                    size: 30,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              task.title,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                decoration: task.isCompleted
                    ? TextDecoration.lineThrough
                    : null,
                color: task.isCompleted
                    ? (isDark ? Colors.white30 : Colors.black38)
                    : (isDark ? Colors.white : const Color(0xFF0F172A)),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (task.description.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                task.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: task.isCompleted
                      ? (isDark ? Colors.white24 : Colors.black26)
                      : (isDark ? Colors.white54 : Colors.black54),
                ),
              ),
            ],
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.category_rounded,
                      size: 14,
                      color: isDark ? Colors.white54 : Colors.black54,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      task.category,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white54 : Colors.black54,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Icon(
                      Icons.calendar_month_rounded,
                      size: 14,
                      color: isDark
                          ? const Color(0xFF00FFC2)
                          : const Color(0xFF6C63FF),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${task.date.day.toString().padLeft(2, '0')}/${task.date.month.toString().padLeft(2, '0')}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: isDark
                            ? const Color(0xFF00FFC2)
                            : const Color(0xFF6C63FF),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnimatedFAB(bool isDark) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 1200),
      curve: Curves.elasticOut,
      builder: (context, value, child) =>
          Transform.scale(scale: value, child: child),
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          _showTaskDialog();
        },
        child: GlassPanel(
          blur: 35,
          opacity: 0.9,
          colorHint: isDark ? const Color(0xFF00FFC2) : const Color(0xFF6C63FF),
          isNeon: true,
          borderRadius: BorderRadius.circular(28),
          padding: const EdgeInsets.all(22),
          child: Icon(
            Icons.add_rounded,
            size: 38,
            color: isDark ? const Color(0xFF0F172A) : Colors.white,
          ),
        ),
      ),
    );
  }
}
