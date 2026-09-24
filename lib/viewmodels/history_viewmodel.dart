import 'package:flutter/foundation.dart';
import '../models/authentication_result.dart';
import '../models/product.dart';
import '../repositories/history_repository.dart';

class HistoryViewModel extends ChangeNotifier {
  final HistoryRepository _historyRepo;
  String _searchQuery = '';
  ProductCategory? _selectedCategory;

  HistoryViewModel({required HistoryRepository historyRepo})
      : _historyRepo = historyRepo {
    _historyRepo.addListener(notifyListeners);
  }

  @override
  void dispose() {
    _historyRepo.removeListener(notifyListeners);
    super.dispose();
  }

  String get searchQuery => _searchQuery;

  List<AuthenticationReport> get allReports => _historyRepo.allReports;

  /// Distinguishes "no scans at all" from "no matches for this filter".
  bool get hasAnyScans => _historyRepo.allReports.isNotEmpty;
  ProductCategory? get selectedCategory => _selectedCategory;

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  void selectCategory(ProductCategory? category) {
    _selectedCategory = category;
    notifyListeners();
  }

  List<AuthenticationReport> get filteredReports {
    return _historyRepo.allReports.where((report) {
      final matchesCategory = _selectedCategory == null ||
          report.product.category == _selectedCategory;

      final matchesQuery = _searchQuery.isEmpty ||
          report.product.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          report.product.brand.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          report.product.model.toLowerCase().contains(_searchQuery.toLowerCase());

      return matchesCategory && matchesQuery;
    }).toList();
  }

  void toggleFavorite(String id) {
    _historyRepo.toggleFavorite(id);
  }
}

