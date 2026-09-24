import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/authentication_result.dart';
import '../models/category_item.dart';

/// Manages all product categories (foundational + dynamically detected from scans).
/// Persists newly discovered categories to SharedPreferences and Cloud Firestore.
class CategoryRepository extends ChangeNotifier {
  static const String _storageKey = 'vericheck_custom_categories';
  SharedPreferences? _prefs;

  final List<CategoryItem> _customCategories = [];

  List<CategoryItem> get allCategories {
    final list = <CategoryItem>[...CategoryItem.defaults];
    for (final custom in _customCategories) {
      if (!list.any((c) => c.id.toLowerCase() == custom.id.toLowerCase())) {
        list.add(custom);
      }
    }
    return List.unmodifiable(list);
  }

  Future<void> loadCategories({SharedPreferences? prefs}) async {
    try {
      _prefs = prefs ?? await SharedPreferences.getInstance();
      final rawList = _prefs?.getStringList(_storageKey);
      _customCategories.clear();
      if (rawList != null) {
        for (final itemStr in rawList) {
          try {
            final json = jsonDecode(itemStr) as Map<String, dynamic>;
            final item = CategoryItem.fromJson(json);
            if (!CategoryItem.defaults.any((d) => d.id.toLowerCase() == item.id.toLowerCase())) {
              _customCategories.add(item);
            }
          } catch (e) {
            if (kDebugMode) debugPrint('[CategoryRepo] parse error: $e');
          }
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[CategoryRepo] load error: $e');
    } finally {
      notifyListeners();
    }
  }

  Future<void> _persist() async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
      final list = _customCategories.map((c) => jsonEncode(c.toJson())).toList();
      await _prefs?.setStringList(_storageKey, list);
    } catch (e) {
      if (kDebugMode) debugPrint('[CategoryRepo] persist error: $e');
    }
  }

  void _syncFirestore(Future<void> Function(DocumentReference userDoc) action) {
    try {
      if (Firebase.apps.isEmpty) return;
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || uid.isEmpty) return;
      final userDoc = FirebaseFirestore.instance.collection('users').doc(uid);
      action(userDoc).catchError((e) {
        if (kDebugMode) debugPrint('[CategoryRepo] Firestore sync error: $e');
      });
    } catch (_) {
      // Ignored for tests where Firebase is not initialized
    }
  }

  /// Syncs remote custom categories down from Firestore
  Future<void> syncFromFirestore() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || uid.isEmpty) return;
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('categories')
          .get();

      bool addedNew = false;
      for (final doc in snapshot.docs) {
        final data = doc.data();
        if (!_customCategories.any((c) => c.id == doc.id) &&
            !CategoryItem.defaults.any((d) => d.id.toLowerCase() == doc.id.toLowerCase())) {
          try {
            final item = CategoryItem.fromJson(data);
            _customCategories.add(item);
            addedNew = true;
          } catch (_) {}
        }
      }

      if (addedNew) {
        await _persist();
        notifyListeners();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[CategoryRepo] syncFromFirestore error: $e');
    }
  }

  /// Clears the local device cache of custom categories only - does NOT
  /// touch the user's Firestore-saved categories. Called on sign-out AND
  /// account deletion - see [HistoryRepository.clearAllLocalData] for why
  /// the same action covers both. Foundational default categories are
  /// never affected; they aren't persisted per-user.
  Future<void> clearAllLocalData() async {
    _customCategories.clear();
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs?.remove(_storageKey);
    notifyListeners();
  }

  /// Dynamically registers a newly scanned category if it doesn't already exist.
  CategoryItem? registerCategory(String name) {
    final clean = name.trim();
    if (clean.isEmpty || clean.toLowerCase() == 'unknown' || clean.toLowerCase() == 'item') {
      return null;
    }

    final existing = allCategories.firstWhere(
      (c) =>
          c.id.toLowerCase() == clean.toLowerCase() ||
          c.label.toLowerCase() == clean.toLowerCase(),
      orElse: () => CategoryItem.fromName(clean),
    );

    // If it's brand new and not in custom categories or defaults
    if (!allCategories.any((c) => c.label.toLowerCase() == clean.toLowerCase())) {
      final newItem = CategoryItem.fromName(clean);
      _customCategories.add(newItem);
      _persist();
      notifyListeners();

      _syncFirestore((doc) => doc.collection('categories').doc(newItem.id).set(newItem.toJson()));
      return newItem;
    }

    return existing;
  }

  /// Scans loaded reports and registers any categories found in user scans.
  void syncFromReports(List<AuthenticationReport> reports) {
    bool hasNew = false;
    for (final r in reports) {
      final label = r.product.categoryLabel.trim();
      if (label.isNotEmpty && label.toLowerCase() != 'unknown') {
        if (!allCategories.any((c) => c.label.toLowerCase() == label.toLowerCase())) {
          final item = CategoryItem.fromName(label);
          _customCategories.add(item);
          hasNew = true;
          _syncFirestore((doc) => doc.collection('categories').doc(item.id).set(item.toJson()));
        }
      }
    }
    if (hasNew) {
      _persist();
      notifyListeners();
    }
  }
}
