import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/authentication_result.dart';
import '../models/category_item.dart';

/// Stores only reports the user actually produced. It starts empty and is
/// never seeded with sample scans (§30, §32).
/// Dual-writes to SharedPreferences (offline-first) and Cloud Firestore.
class HistoryRepository extends ChangeNotifier {
  final List<AuthenticationReport> _reports = [];

  static const String _storageKey = 'vericheck_reports_v2';
  SharedPreferences? _prefs;
  bool _isLoaded = false;

  bool get isLoaded => _isLoaded;
  bool get isEmpty => _reports.isEmpty;

  Future<void> loadPersistedReports({SharedPreferences? prefs}) async {
    try {
      _prefs = prefs ?? await SharedPreferences.getInstance();
      final list = _prefs?.getStringList(_storageKey);
      _reports.clear();
      if (list != null) {
        for (final raw in list) {
          try {
            _reports.add(AuthenticationReport.fromJson(jsonDecode(raw) as Map<String, dynamic>));
          } catch (e) {
            if (kDebugMode) debugPrint('[HistoryRepository] skipped unreadable report: $e');
          }
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[HistoryRepository] load error: $e');
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
        _reports.map((r) => jsonEncode(r.toJson())).toList(),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[HistoryRepository] persist error: $e');
    }
  }

  void _syncFirestore(Future<void> Function(DocumentReference userDoc) action) {
    try {
      if (Firebase.apps.isEmpty) return;
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || uid.isEmpty) return;
      final userDoc = FirebaseFirestore.instance.collection('users').doc(uid);
      action(userDoc).catchError((e) {
        if (kDebugMode) debugPrint('[HistoryRepository] Firestore sync error: $e');
      });
    } catch (_) {
      // Firebase might not be initialized in unit tests without mocks
    }
  }

  /// Syncs remote reports down from Firestore to merge with local offline cache
  Future<void> syncFromFirestore() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || uid.isEmpty) return;
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('reports')
          .get();

      bool addedNew = false;
      for (final doc in snapshot.docs) {
        final data = doc.data();
        if (!_reports.any((r) => r.id == doc.id)) {
          try {
            final report = AuthenticationReport.fromJson(data);
            _reports.add(report);
            addedNew = true;
          } catch (_) {}
        }
      }

      if (addedNew) {
        _reports.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        await persist();
        notifyListeners();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[HistoryRepository] syncFromFirestore error: $e');
    }
  }

  List<AuthenticationReport> get allReports => List.unmodifiable(_reports);

  List<AuthenticationReport> get favoriteReports =>
      _reports.where((r) => r.isFavorite).toList();

  List<AuthenticationReport> getByCategoryItem(CategoryItem categoryItem) {
    final targetLabel = categoryItem.label.trim().toLowerCase();
    return _reports.where((r) {
      if (categoryItem.category != null &&
          r.product.category == categoryItem.category &&
          r.product.customCategory == null) {
        return true;
      }
      return r.product.categoryLabel.trim().toLowerCase() == targetLabel;
    }).toList();
  }

  /// Image paths owned by a report, for cleanup when it is deleted.
  Iterable<String> _imagePathsOf(AuthenticationReport r) sync* {
    for (final e in r.evidenceItems) {
      if (e.capturedImagePath.isNotEmpty) yield e.capturedImagePath;
    }
    if (r.product.imageAsset.isNotEmpty && !r.product.imageAsset.startsWith('assets/')) {
      yield r.product.imageAsset;
    }
  }

  void toggleFavorite(String reportId) {
    final index = _reports.indexWhere((r) => r.id == reportId);
    if (index == -1) return;
    final updatedFavorite = !_reports[index].isFavorite;
    _reports[index] = _reports[index].copyWith(isFavorite: updatedFavorite);
    persist();
    notifyListeners();

    _syncFirestore((doc) => doc.collection('reports').doc(reportId).update({
      'isFavorite': updatedFavorite,
    }));
  }

  void addReport(AuthenticationReport report) {
    _reports.insert(0, report);
    persist();
    notifyListeners();

    _syncFirestore((doc) => doc.collection('reports').doc(report.id).set(report.toJson()));
  }

  void updateReport(AuthenticationReport report) {
    final index = _reports.indexWhere((r) => r.id == report.id);
    if (index == -1) {
      addReport(report);
      return;
    }
    _reports[index] = report;
    persist();
    notifyListeners();

    _syncFirestore((doc) => doc.collection('reports').doc(report.id).set(report.toJson()));
  }

  /// Returns the image paths the deleted report owned so the caller can remove
  /// the files from disk.
  List<String> deleteReport(String reportId) {
    final index = _reports.indexWhere((r) => r.id == reportId);
    if (index == -1) return const [];
    final orphaned = _imagePathsOf(_reports[index]).toList();
    _reports.removeAt(index);
    persist();
    notifyListeners();

    _syncFirestore((doc) => doc.collection('reports').doc(reportId).delete());
    return orphaned;
  }

  /// Clears the local device cache only - does NOT touch the user's
  /// Firestore-saved reports. Called on sign-out AND account deletion alike:
  /// for sign-out the account is still reachable later (syncFromFirestore
  /// repopulates on next login), and for deletion the Cloud Function already
  /// wipes the Firestore side - either way, this only ever needs to stop the
  /// next account that signs in on this device from inheriting stale local
  /// data (the deleted-account "resurrection" bug).
  Future<List<String>> clearAllLocalData() async {
    final orphaned = _reports.expand(_imagePathsOf).toList();
    _reports.clear();
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs?.remove(_storageKey);
    notifyListeners();
    return orphaned;
  }
}
