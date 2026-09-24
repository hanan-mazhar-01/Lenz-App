import 'package:flutter/foundation.dart';
import '../models/authentication_result.dart';
import '../models/product.dart';
import '../repositories/history_repository.dart';

class FavoritesViewModel extends ChangeNotifier {
  final HistoryRepository _historyRepo;
  ProductCategory? _selectedCategory;

  FavoritesViewModel({required HistoryRepository historyRepo})
      : _historyRepo = historyRepo {
    _historyRepo.addListener(notifyListeners);
  }

  @override
  void dispose() {
    _historyRepo.removeListener(notifyListeners);
    super.dispose();
  }

  ProductCategory? get selectedCategory => _selectedCategory;

  void selectCategory(ProductCategory? category) {
    _selectedCategory = category;
    notifyListeners();
  }

  List<AuthenticationReport> get allFavorites => _historyRepo.favoriteReports;

  List<AuthenticationReport> get favoriteReports {
    return _historyRepo.favoriteReports.where((report) {
      if (_selectedCategory == null) return true;
      return report.product.category == _selectedCategory;
    }).toList();
  }

  void toggleFavorite(String id) {
    _historyRepo.toggleFavorite(id);
  }
}

