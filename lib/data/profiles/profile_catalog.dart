import '../evidence_profiles.dart';
import 'fashion_profiles.dart';
import 'other_profiles.dart';
import 'watch_profiles.dart';

/// Every evidence profile the app knows. To support a new category or a
/// specific model, add a profile here (and a category code the
/// identification step can return); nothing else needs to change.
abstract final class ProfileCatalog {
  static const generic = OtherProfiles.generic;

  static const List<EvidenceProfile> all = [
    WatchProfiles.appleWatch,
    WatchProfiles.smartwatch,
    WatchProfiles.mechanicalWatch,
    FashionProfiles.footwear,
    FashionProfiles.handbag,
    FashionProfiles.wallet,
    FashionProfiles.eyewear,
    FashionProfiles.clothing,
    FashionProfiles.accessory,
    OtherProfiles.generic,
  ];
}
