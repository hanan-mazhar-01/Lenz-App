// Home / History / Favorites / Category / tab shell: behaviour + layout
// checks at 390x844 and 320x640 @ text scale 1.3 (no overflow), and, with
// LENZ_SCREENS_DUMP=1, PNG renders for side-by-side comparison with the
// prototype references:
//
//   LENZ_SCREENS_DUMP=1 flutter test test/screens/home_screens_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:replica_detector/models/category_item.dart';
import 'package:replica_detector/models/product.dart';
import 'package:replica_detector/views/category/category_browse_screen.dart';
import 'package:replica_detector/views/favorites/favorites_screen.dart';
import 'package:replica_detector/views/history/history_screen.dart';
import 'package:replica_detector/views/home/home_screen.dart';
import 'package:replica_detector/views/main_navigation_shell.dart';
import 'package:replica_detector/widgets/navigation/lenz_tab_bar.dart';
import 'package:replica_detector/widgets/tour/home_tour_card.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:showcaseview/showcaseview.dart';

import '../ui_kit/ui_test_utils.dart' show loadNunito;
import 'home_test_support.dart';

final _keys = List.generate(5, (_) => GlobalKey());

HomeScreen _home({VoidCallback? onPremium, ValueChanged<CategoryItem>? onCategory}) => HomeScreen(
  onStartScan: () {},
  onOpenReport: (_) {},
  onOpenCategory: onCategory ?? (_) {},
  onOpenProfile: () {},
  onOpenHistory: () {},
  onOpenPremium: onPremium,
  tourHeroKey: _keys[0],
  tourBrowseKey: _keys[1],
  tourRecentKey: _keys[2],
  tourProfileKey: _keys[3],
  tourNavKey: _keys[4],
);

/// A tab screen with the floating tab bar on top, like the shell lays it out.
Widget _withBar(Widget screen, int tab) => Stack(
  children: [
    Positioned.fill(child: screen),
    Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: LenzTabBar(currentIndex: tab, onTab: (_) {}, onScan: () {}),
    ),
  ],
);

const _small = Size(320, 640);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadNunito);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Home', () {
    screenTest('non-premium signed-in: real stats + Pro promo', (tester) async {
      await preloadArt(tester);
      final env = ScreenEnv(reports: sampleReports(), user: profile(scans: 3));
      await pumpScreen(tester, 'home_free', env.wrap(_withBar(_home(), 0)));
      expect(find.text('Welcome back'), findsOneWidget);
      expect(find.text('Hi, Alex 👋'), findsOneWidget);
      expect(find.text('Upgrade to Lenz Pro'), findsOneWidget);
      expect(find.text('Create an account'), findsNothing);
      expect(find.text('Scans left'), findsOneWidget);
      expect(find.text('3'), findsOneWidget); // scans left
      expect(find.text('5'), findsOneWidget); // checks run
      expect(find.text('2'), findsWidgets); // authentic (+ category counts)
      expect(find.text('Neverfull MM'), findsOneWidget);
      expect(find.text('Louis Vuitton · Bags'), findsOneWidget);
      expect(find.text('2 checks'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    screenTest('guest: create-account promo, never Pro', (tester) async {
      await preloadArt(tester);
      final env = ScreenEnv(
        anonymous: true,
        reports: sampleReports().take(2).toList(),
        user: profile(name: 'Guest Collector', scans: 1),
      );
      await pumpScreen(tester, 'home_guest', env.wrap(_withBar(_home(), 0)));
      expect(find.text('Guest mode'), findsOneWidget);
      expect(find.text('Hi, Guest 👋'), findsOneWidget);
      expect(find.text('Create an account'), findsOneWidget);
      expect(find.textContaining('Lenz Pro'), findsNothing);
      expect(find.textContaining('Upgrade'), findsNothing);
      expect(find.text('PRO'), findsNothing);
    });

    screenTest('premium: no promo, unlimited stat', (tester) async {
      await preloadArt(tester);
      final env = ScreenEnv(reports: sampleReports(), user: profile(premium: true));
      await pumpScreen(tester, 'home_premium', env.wrap(_withBar(_home(), 0)));
      expect(find.text('Upgrade to Lenz Pro'), findsNothing);
      expect(find.text('Create an account'), findsNothing);
      expect(find.text('Unlimited'), findsOneWidget);
    });

    screenTest('empty: Lenz empty state with first-scan button', (tester) async {
      await preloadArt(tester);
      final env = ScreenEnv();
      await pumpScreen(
        tester,
        'home_empty',
        env.wrap(_withBar(_home(), 0)),
        after: () async {
          await tester.drag(find.byType(SingleChildScrollView).first, const Offset(0, -500));
        },
      );
      expect(find.text('No checks yet'), findsOneWidget);
      expect(find.text('Start first scan'), findsOneWidget);
      expect(find.text('0 checks'), findsWidgets);
    });

    screenTest('category card opens the category', (tester) async {
      await preloadArt(tester);
      CategoryItem? opened;
      final env = ScreenEnv(reports: sampleReports());
      await pumpScreen(
        tester,
        'home_scrolled',
        env.wrap(_withBar(_home(onCategory: (c) => opened = c), 0)),
        after: () async {
          await tester.drag(find.byType(SingleChildScrollView).first, const Offset(0, -560));
        },
      );
      await tester.tap(find.text('Bags'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(opened?.label, 'Bags');
    });

    screenTest('small phone + text scale 1.3 does not overflow', (tester) async {
      await preloadArt(tester);
      for (final guest in [false, true]) {
        final env = ScreenEnv(anonymous: guest, reports: sampleReports());
        await pumpScreen(
          tester,
          'home_small_${guest ? 'guest' : 'free'}',
          env.wrap(_withBar(_home(), 0), textScale: 1.3),
          size: _small,
        );
        expect(tester.takeException(), isNull);
      }
      final env = ScreenEnv();
      await pumpScreen(
        tester,
        'home_small_empty',
        env.wrap(_withBar(_home(), 0), textScale: 1.3),
        size: _small,
        after: () async {
          await tester.drag(find.byType(SingleChildScrollView).first, const Offset(0, -700));
        },
      );
      expect(tester.takeException(), isNull);
    });

    screenTest('tour step renders the Lenz tour card', (tester) async {
      await preloadArt(tester);
      final env = ScreenEnv(reports: sampleReports());
      await pumpScreen(
        tester,
        'home_tour',
        env.wrap(_withBar(_home(), 0)),
        settleMs: 2400,
        after: () async {
          await tester.pump(const Duration(milliseconds: 600));
          ShowcaseView.get().startShowCase([_keys[0], _keys[1]]);
        },
      );
      expect(find.byType(HomeTourCard), findsOneWidget);
      expect(find.text('Scan anything'), findsOneWidget);
      expect(find.text('1 of 5'), findsOneWidget);
      expect(find.text('Next'), findsOneWidget);
      expect(find.text('Skip'), findsOneWidget);
      ShowcaseView.get().dismiss();
      await tester.pump(const Duration(milliseconds: 600));
    });
  });

  screenTest('tour card fits a small phone at text scale 1.3', (tester) async {
    await preloadArt(tester);
    final env = ScreenEnv(reports: sampleReports());
    await pumpScreen(
      tester,
      'home_tour_small',
      env.wrap(_withBar(_home(), 0), textScale: 1.3),
      size: _small,
      settleMs: 2400,
      after: () async {
        await tester.pump(const Duration(milliseconds: 600));
        ShowcaseView.get().startShowCase([_keys[2], _keys[3]]);
      },
    );
    expect(find.byType(HomeTourCard), findsOneWidget);
    expect(tester.takeException(), isNull);
    ShowcaseView.get().dismiss();
    await tester.pump(const Duration(milliseconds: 600));
  });

  group('History', () {
    screenTest('list with search + category chips', (tester) async {
      await preloadArt(tester);
      final env = ScreenEnv(reports: sampleReports());
      await pumpScreen(
        tester,
        'history',
        env.wrap(_withBar(HistoryScreen(onOpenReport: (_) {}), 1)),
      );
      expect(find.text('Every check you ran, in one place.'), findsOneWidget);
      expect(find.text('Neverfull MM'), findsOneWidget);
      expect(find.text('Bags'), findsOneWidget); // category chip
      await tester.enterText(find.byType(TextField), 'rolex');
      await tester.pump(const Duration(milliseconds: 800));
      expect(find.text('Submariner Date'), findsOneWidget);
      expect(find.text('Neverfull MM'), findsNothing);
      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pump(const Duration(milliseconds: 800));
      expect(find.text('No matches'), findsOneWidget);
    });

    screenTest('empty + small phone', (tester) async {
      await preloadArt(tester);
      await pumpScreen(
        tester,
        'history_empty',
        ScreenEnv().wrap(_withBar(HistoryScreen(onOpenReport: (_) {}, onStartScan: () {}), 1)),
      );
      expect(find.text('No scans yet'), findsOneWidget);
      await pumpScreen(
        tester,
        'history_small',
        ScreenEnv(reports: sampleReports())
            .wrap(_withBar(HistoryScreen(onOpenReport: (_) {}), 1), textScale: 1.3),
        size: _small,
      );
      expect(tester.takeException(), isNull);
      await pumpScreen(
        tester,
        'history_small_empty',
        ScreenEnv().wrap(
          _withBar(HistoryScreen(onOpenReport: (_) {}, onStartScan: () {}), 1),
          textScale: 1.3,
        ),
        size: _small,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('Favorites', () {
    screenTest('grid of real favourites', (tester) async {
      await preloadArt(tester);
      final env = ScreenEnv(reports: sampleReports());
      await pumpScreen(
        tester,
        'favorites',
        env.wrap(_withBar(FavoritesScreen(onOpenReport: (_) {}), 2)),
      );
      expect(find.text('Reports you want to keep close.'), findsOneWidget);
      expect(find.text('Neverfull MM'), findsOneWidget);
      expect(find.text('Air Jordan 1 High OG'), findsOneWidget);
      expect(find.text('Submariner Date'), findsNothing);
    });

    screenTest('empty + small phone', (tester) async {
      await preloadArt(tester);
      await pumpScreen(
        tester,
        'favorites_empty',
        ScreenEnv().wrap(_withBar(FavoritesScreen(onOpenReport: (_) {}), 2)),
      );
      expect(find.text('Nothing saved yet'), findsOneWidget);
      await pumpScreen(
        tester,
        'favorites_small',
        ScreenEnv(reports: sampleReports())
            .wrap(_withBar(FavoritesScreen(onOpenReport: (_) {}), 2), textScale: 1.3),
        size: _small,
      );
      expect(tester.takeException(), isNull);
      await pumpScreen(
        tester,
        'favorites_small_empty',
        ScreenEnv().wrap(_withBar(FavoritesScreen(onOpenReport: (_) {}), 2), textScale: 1.3),
        size: _small,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('Category', () {
    screenTest('bags with checks, watches empty, small phone', (tester) async {
      await preloadArt(tester);
      final env = ScreenEnv(reports: sampleReports());
      Widget cat(ProductCategory c) => CategoryBrowseScreen(
        category: CategoryItem.fromProductCategory(c),
        onOpenReport: (_) {},
        onBack: () {},
        onStartScan: () {},
      );
      await pumpScreen(tester, 'category_bags', env.wrap(cat(ProductCategory.bags)));
      expect(find.text('2 checks so far'), findsOneWidget);
      expect(find.text('Scan bags'), findsOneWidget);
      await pumpScreen(tester, 'category_empty', env.wrap(cat(ProductCategory.watches)));
      // Watches has one sample report.
      expect(find.text('1 check so far'), findsOneWidget);
      await pumpScreen(tester, 'category_clothing_empty', env.wrap(cat(ProductCategory.clothing)));
      expect(find.text('No Clothing scans yet'), findsOneWidget);
      await pumpScreen(
        tester,
        'category_small',
        env.wrap(cat(ProductCategory.bags), textScale: 1.3),
        size: _small,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('Guest mode: nothing is saved, and the screens say so', () {
    screenTest('History asks a guest to create an account and has no search', (tester) async {
      await preloadArt(tester);
      final env = ScreenEnv(anonymous: true);
      await pumpScreen(tester, 'history_guest', env.wrap(_withBar(HistoryScreen(onOpenReport: (_) {}, onStartScan: () {}), 1)));
      expect(find.text('Create an account to save scans'), findsOneWidget);
      expect(find.text('Create account'), findsOneWidget);
      expect(find.text('Search your checks...'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    screenTest('Saved asks a guest to create an account to keep favorites', (tester) async {
      await preloadArt(tester);
      final env = ScreenEnv(anonymous: true);
      await pumpScreen(tester, 'favorites_guest', env.wrap(_withBar(FavoritesScreen(onOpenReport: (_) {}), 2)));
      expect(find.text('Create an account to save favorites'), findsOneWidget);
      expect(find.text('Create account'), findsOneWidget);
      expect(find.text('Nothing saved yet'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    screenTest('a signed-in user keeps the normal empty states', (tester) async {
      await preloadArt(tester);
      final env = ScreenEnv();
      await pumpScreen(tester, 'history_user_empty', env.wrap(_withBar(HistoryScreen(onOpenReport: (_) {}, onStartScan: () {}), 1)));
      expect(find.text('No scans yet'), findsOneWidget);
      expect(find.text('Create an account to save scans'), findsNothing);
    });

    screenTest('Home\'s recent checks card asks a guest to create an account', (tester) async {
      await preloadArt(tester);
      final env = ScreenEnv(anonymous: true);
      await pumpScreen(tester, 'home_guest_recent', env.wrap(_withBar(_home(), 0)));
      await tester.dragUntilVisible(find.text('Guest scans are not saved'), find.byType(SingleChildScrollView).first, const Offset(0, -300));
      expect(find.text('Guest scans are not saved'), findsOneWidget);
      expect(find.text('Create account'), findsOneWidget);
    });
  });

  group('Shell', () {
    screenTest('tab bar switches tabs and hides on a layer', (tester) async {
      await preloadArt(tester);
      // Tour already seen for this uid so it does not auto-start.
      SharedPreferences.setMockInitialValues({'home_tour_seen_test-uid': true});
      final env = ScreenEnv(reports: sampleReports());
      final shell = env.wrap(const MainNavigationShell());
      final key = await pumpScreen(tester, 'shell_home', shell);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(tester.takeException(), isNull);

      Future<void> tab(String label, String dump) async {
        await tester.tap(find.descendant(of: find.byType(LenzTabBar), matching: find.text(label)));
        for (var i = 0; i < 12; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        await dumpNow(tester, key, dump);
      }

      await tab('History', 'shell_history');
      expect(find.text('Every check you ran, in one place.'), findsOneWidget);
      await tab('Saved', 'shell_favorites');
      expect(find.text('Reports you want to keep close.'), findsOneWidget);
      await tab('Profile', 'shell_profile');
      await tab('Home', 'shell_home2');

      // Category layer slides in; the tab bar hides.
      await tester.drag(find.byType(SingleChildScrollView).first, const Offset(0, -560));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Watches'));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('1 check so far'), findsOneWidget);
      final bar = tester.widget<LenzTabBar>(find.byType(LenzTabBar));
      expect(bar.hidden, isTrue);
      await dumpNow(tester, key, 'shell_category');

      // System back closes the layer first, then walks back to Home.
      Future<void> back() async {
        await tester.binding.handlePopRoute();
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      await back();
      expect(find.text('1 check so far'), findsNothing);
      expect(tester.widget<LenzTabBar>(find.byType(LenzTabBar)).hidden, isFalse);
      expect(tester.widget<LenzTabBar>(find.byType(LenzTabBar)).currentIndex, 0);
      await tab('History', 'shell_history_back');
      expect(tester.widget<LenzTabBar>(find.byType(LenzTabBar)).currentIndex, 1);
      await back();
      expect(tester.widget<LenzTabBar>(find.byType(LenzTabBar)).currentIndex, 0);
    });
  });
}
