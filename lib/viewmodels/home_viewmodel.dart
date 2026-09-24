import 'package:flutter/foundation.dart';
import '../models/authentication_result.dart';
import '../models/category_item.dart';
import '../repositories/category_repository.dart';
import '../repositories/history_repository.dart';

class HomeViewModel extends ChangeNotifier {
  final HistoryRepository _historyRepo;
  final CategoryRepository _categoryRepo;
  CategoryItem? _selectedCategoryItem;

  HomeViewModel({
    required HistoryRepository historyRepo,
    required CategoryRepository categoryRepo,
  })  : _historyRepo = historyRepo,
        _categoryRepo = categoryRepo {
    _historyRepo.addListener(_onHistoryChanged);
    _categoryRepo.addListener(_onCategoriesChanged);
    _syncCategories();
  }

  void _onHistoryChanged() {
    _syncCategories();
    notifyListeners();
  }

  void _onCategoriesChanged() {
    notifyListeners();
  }

  void _syncCategories() {
    _categoryRepo.syncFromReports(_historyRepo.allReports);
  }

  List<CategoryItem> get categories => _categoryRepo.allCategories;

  CategoryItem? get selectedCategoryItem => _selectedCategoryItem;

  /// Most recent first, filtered by selected category, capped for the home surface.
  List<AuthenticationReport> get filteredReports {
    final all = _historyRepo.allReports;
    if (_selectedCategoryItem == null) {
      return all.take(5).toList();
    }

    final target = _selectedCategoryItem!.label.toLowerCase();
    final targetId = _selectedCategoryItem!.id.toLowerCase();

    final filtered = all.where((r) {
      final p = r.product;
      final pLabel = p.categoryLabel.toLowerCase();
      final pEnum = p.category.name.toLowerCase();
      return pLabel == target || pEnum == targetId;
    }).toList();

    return filtered.take(5).toList();
  }

  @override
  void dispose() {
    _historyRepo.removeListener(_onHistoryChanged);
    _categoryRepo.removeListener(_onCategoriesChanged);
    super.dispose();
  }
}
