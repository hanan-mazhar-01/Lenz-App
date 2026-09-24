import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:replica_detector/models/category_item.dart';
import 'package:replica_detector/models/product.dart';
import 'package:replica_detector/repositories/authentication_repository.dart';
import 'package:replica_detector/repositories/category_repository.dart';
import 'package:replica_detector/repositories/collection_repository.dart';
import 'package:replica_detector/repositories/gemini_authentication_repository.dart';
import 'package:replica_detector/repositories/history_repository.dart';
import 'package:replica_detector/services/storage_service.dart';
import 'package:replica_detector/viewmodels/favorites_viewmodel.dart';
import 'package:replica_detector/viewmodels/history_viewmodel.dart';
import 'package:replica_detector/viewmodels/home_viewmodel.dart';
import 'package:replica_detector/views/category/category_browse_screen.dart';
import 'package:replica_detector/views/collection/collection_screen.dart';
import 'package:replica_detector/views/favorites/favorites_screen.dart';
import 'package:replica_detector/views/history/history_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_gemini.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late HistoryRepository history;
  late CollectionRepository collection;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    history = HistoryRepository();
    collection = CollectionRepository();
  });

  Widget wrap(Widget child) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<StorageService>.value(value: StorageService()),
        ChangeNotifierProvider<HistoryRepository>.value(value: history),
        ChangeNotifierProvider<CollectionRepository>.value(value: collection),
        Provider<AuthenticationRepository>.value(
          value: AuthenticationRepository(
            geminiRepo: GeminiAuthenticationRepository(
              geminiService: FakeGeminiService(),
              imagePrep: FakeImagePreparationService(),
            ),
          ),
        ),
        ChangeNotifierProvider<HomeViewModel>(create: (_) => HomeViewModel(historyRepo: history, categoryRepo: CategoryRepository())),
        ChangeNotifierProvider<HistoryViewModel>(create: (_) => HistoryViewModel(historyRepo: history)),
        ChangeNotifierProvider<FavoritesViewModel>(create: (_) => FavoritesViewModel(historyRepo: history)),
      ],
      child: MaterialApp(home: child),
    );
  }

  group('Empty states instead of sample content (§30, §31, §33, §34)', () {
    testWidgets('history shows an empty state and no product cards', (tester) async {
      await tester.pumpWidget(wrap(HistoryScreen(onOpenReport: (_) {}, onStartScan: () {})));
      await tester.pump();

      expect(find.text('No scans yet'), findsOneWidget);
      expect(find.text('Scan an Item'), findsOneWidget);
      expect(find.textContaining('Rolex'), findsNothing);
      expect(find.textContaining('Louis Vuitton'), findsNothing);
      expect(find.textContaining('Nike'), findsNothing);
    });

    testWidgets('favourites shows an empty state', (tester) async {
      await tester.pumpWidget(wrap(FavoritesScreen(onOpenReport: (_) {})));
      await tester.pump();

      expect(find.text('No favourites yet'), findsOneWidget);
      expect(find.textContaining('Gucci'), findsNothing);
    });

    testWidgets('the collection shows an empty state with a scan CTA', (tester) async {
      await tester.pumpWidget(wrap(CollectionScreen(onBack: () {}, onScanItem: () {})));
      await tester.pump();

      expect(find.text('Your collection is empty'), findsOneWidget);
      expect(find.text('Scan an Item'), findsOneWidget);
      expect(find.textContaining(r'$'), findsNothing, reason: 'No invented portfolio value');
    });

    testWidgets('a category with no scans says so', (tester) async {
      await tester.pumpWidget(wrap(CategoryBrowseScreen(
        category: CategoryItem.fromProductCategory(ProductCategory.watches),
        onOpenReport: (_) {},
        onBack: () {},
      )));
      await tester.pump();

      expect(find.text('No Watches Scans Yet'), findsOneWidget);
      expect(find.text('0 verified items'), findsOneWidget);
      expect(find.textContaining('Submariner'), findsNothing);
    });
  });
}
