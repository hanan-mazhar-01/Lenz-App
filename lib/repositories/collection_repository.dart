import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/collection_item.dart';
import '../models/product.dart';

/// Holds only items the user explicitly saved from a real report. Starts
/// empty and is never seeded (§30, §47).
/// Dual-writes to SharedPreferences (offline-first) and Cloud Firestore.
class CollectionRepository extends ChangeNotifier {
  final List<CollectionItem> _items = [];

  static const String _storageKey = 'vericheck_collection_v2';
  SharedPreferences? _prefs;
  bool _isLoaded = false;

  bool get isLoaded => _isLoaded;
  bool get isEmpty => _items.isEmpty;

  Future<void> load({SharedPreferences? prefs}) async {
    try {
      _prefs = prefs ?? await SharedPreferences.getInstance();
      final list = _prefs?.getStringList(_storageKey);
      _items.clear();
      if (list != null) {
        for (final raw in list) {
          try {
            _items.add(CollectionItem.fromJson(jsonDecode(raw) as Map<String, dynamic>));
          } catch (e) {
            if (kDebugMode) debugPrint('[CollectionRepository] skipped unreadable item: $e');
          }
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[CollectionRepository] load error: $e');
    } finally {
      _isLoaded = true;
      notifyListeners();
    }
  }

  Future<void> persist() async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
      await _prefs?.setStringList(
        _storageKey,
        _items.map((i) => jsonEncode(i.toJson())).toList(),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[CollectionRepository] persist error: $e');
    }
  }

  void _syncFirestore(Future<void> Function(DocumentReference userDoc) action) {
    try {
      if (Firebase.apps.isEmpty) return;
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || uid.isEmpty) return;
      final userDoc = FirebaseFirestore.instance.collection('users').doc(uid);
      action(userDoc).catchError((e) {
        if (kDebugMode) debugPrint('[CollectionRepository] Firestore sync error: $e');
      });
    } catch (_) {
      // Ignored for tests where Firebase is not initialized
    }
  }

  /// Syncs remote collection items down from Firestore to merge with local offline cache
  Future<void> syncFromFirestore() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || uid.isEmpty) return;
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('collection')
          .get();

      bool addedNew = false;
      for (final doc in snapshot.docs) {
        final data = doc.data();
        if (!_items.any((i) => i.id == doc.id)) {
          try {
            final item = CollectionItem.fromJson(data);
            _items.add(item);
            addedNew = true;
          } catch (_) {}
        }
      }

      if (addedNew) {
        await persist();
        notifyListeners();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[CollectionRepository] syncFromFirestore error: $e');
    }
  }

  List<CollectionItem> get allItems => List.unmodifiable(_items);

  int get totalCount => _items.length;

  List<CollectionItem> getByCategory(ProductCategory? category) {
    if (category == null) return allItems;
    return _items.where((item) => item.category == category).toList();
  }

  bool containsReport(String reportId) => _items.any((i) => i.sourceReportId == reportId);

  void addItem(CollectionItem item) {
    if (item.sourceReportId != null && containsReport(item.sourceReportId!)) return;
    _items.insert(0, item);
    persist();
    notifyListeners();

    _syncFirestore((doc) => doc.collection('collection').doc(item.id).set(item.toJson()));
  }

  void removeItem(String id) {
    _items.removeWhere((item) => item.id == id);
    persist();
    notifyListeners();

    _syncFirestore((doc) => doc.collection('collection').doc(id).delete());
  }

  /// Clears the local device cache only - does NOT touch the user's
  /// Firestore-saved collection. Called on sign-out AND account deletion -
  /// see [HistoryRepository.clearAllLocalData] for why the same action
  /// covers both.
  Future<void> clearAllLocalData() async {
    _items.clear();
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs?.remove(_storageKey);
    notifyListeners();
  }
}
