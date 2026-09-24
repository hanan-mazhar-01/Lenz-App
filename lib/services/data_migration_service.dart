import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DataMigrationService {
  static const String _keyReports = 'vericheck_reports_v2';
  static const String _keyCollection = 'vericheck_collection_v2';
  static const String _keyCategories = 'vericheck_custom_categories';

  /// Runs a one-time migration from local SharedPreferences to the user's
  /// Firestore subcollections if they have not been migrated yet.
  static Future<void> migrateOfflineDataIfNeeded({
    required String uid,
    SharedPreferences? prefs,
    FirebaseFirestore? firestore,
  }) async {
    if (uid.isEmpty) return;

    try {
      final p = prefs ?? await SharedPreferences.getInstance();
      if (firestore == null && Firebase.apps.isEmpty) {
        return;
      }
      final db = firestore ?? FirebaseFirestore.instance;

      final migrationFlag = 'vericheck_migrated_to_firestore_$uid';
      if (p.getBool(migrationFlag) == true) {
        return;
      }

      final userDoc = db.collection('users').doc(uid);

      // 1. Migrate Reports
      final rawReports = p.getStringList(_keyReports);
      if (rawReports != null && rawReports.isNotEmpty) {
        final reportsSnap = await userDoc.collection('reports').limit(1).get();
        if (reportsSnap.docs.isEmpty) {
          final batch = db.batch();
          for (final raw in rawReports) {
            try {
              final json = jsonDecode(raw) as Map<String, dynamic>;
              final id = json['id'] as String? ?? 'rep_${DateTime.now().millisecondsSinceEpoch}';
              batch.set(userDoc.collection('reports').doc(id), json);
            } catch (e) {
              if (kDebugMode) debugPrint('[DataMigration] Skipped bad report: $e');
            }
          }
          await batch.commit();
          if (kDebugMode) debugPrint('[DataMigration] Migrated ${rawReports.length} reports');
        }
      }

      // 2. Migrate Collection
      final rawCollection = p.getStringList(_keyCollection);
      if (rawCollection != null && rawCollection.isNotEmpty) {
        final collectionSnap = await userDoc.collection('collection').limit(1).get();
        if (collectionSnap.docs.isEmpty) {
          final batch = db.batch();
          for (final raw in rawCollection) {
            try {
              final json = jsonDecode(raw) as Map<String, dynamic>;
              final id = json['id'] as String? ?? 'item_${DateTime.now().millisecondsSinceEpoch}';
              batch.set(userDoc.collection('collection').doc(id), json);
            } catch (e) {
              if (kDebugMode) debugPrint('[DataMigration] Skipped bad item: $e');
            }
          }
          await batch.commit();
          if (kDebugMode) debugPrint('[DataMigration] Migrated ${rawCollection.length} collection items');
        }
      }

      // 3. Migrate Custom Categories
      final rawCategories = p.getStringList(_keyCategories);
      if (rawCategories != null && rawCategories.isNotEmpty) {
        final catSnap = await userDoc.collection('categories').limit(1).get();
        if (catSnap.docs.isEmpty) {
          final batch = db.batch();
          for (final raw in rawCategories) {
            try {
              final json = jsonDecode(raw) as Map<String, dynamic>;
              final id = json['id'] as String? ?? 'cat_${DateTime.now().millisecondsSinceEpoch}';
              batch.set(userDoc.collection('categories').doc(id), json);
            } catch (e) {
              if (kDebugMode) debugPrint('[DataMigration] Skipped bad category: $e');
            }
          }
          await batch.commit();
          if (kDebugMode) debugPrint('[DataMigration] Migrated ${rawCategories.length} categories');
        }
      }

      await p.setBool(migrationFlag, true);
      if (kDebugMode) debugPrint('[DataMigration] Migration marked complete for $uid');
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[DataMigration] Migration error: $e');
      }
    }
  }
}
