import '../../models/capture_guide.dart';
import '../../models/evidence_record.dart';
import '../evidence_profiles.dart';
import 'shared_checkpoints.dart';

/// The generic fallback profile.
abstract final class OtherProfiles {
  // ============================================================ generic
  /// Used for categories without a reliable profile. It invents no
  /// product-specific criteria: it can spot obvious imitation and poor
  /// execution, but never calls an item authentic.
  static const generic = EvidenceProfile(
    id: 'generic',
    name: 'General item',
    categoryCodes: {'OTHER', 'ACCESSORY', 'WATCH', 'HANDBAG', 'SNEAKER', 'SHOE', 'CLOTHING', 'WALLET', 'SUNGLASSES', 'EYEGLASSES'},
    isGeneric: true,
    policy: VerdictPolicy(allowsAuthentic: false),
    requests: [
      PhotoRequestTemplate(
        id: 'brand_marking',
        title: 'Brand name or logo',
        instruction: 'Take a sharp close-up of the brand name or logo.',
        why: 'An altered or look-alike brand marking is the clearest sign of imitation.',
        guide: CaptureGuideType.macro,
        tips: CaptureTips.closeUp,
        checkpointIds: ['brand_marking', 'gn_print_quality'],
        basePriority: 1,
        aliases: ['logo', 'brand', 'name'],
      ),
      PhotoRequestTemplate(
        id: 'label',
        title: 'Label or markings',
        instruction: 'Photograph any label, tag or printed markings so the text is readable.',
        why: 'Labels show print quality and product information.',
        guide: CaptureGuideType.label,
        tips: CaptureTips.text,
        checkpointIds: ['gn_label', 'gn_print_quality'],
        basePriority: 2,
        aliases: ['label', 'tag', 'markings', 'text'],
      ),
      PhotoRequestTemplate(
        id: 'construction',
        title: 'Construction close-up',
        instruction: 'Take a close-up of a seam, join or edge.',
        why: 'Construction shows manufacturing care.',
        guide: CaptureGuideType.macro,
        tips: CaptureTips.closeUp,
        checkpointIds: ['gn_construction'],
        basePriority: 3,
        aliases: ['seam', 'edge', 'join', 'construction'],
      ),
      PhotoRequestTemplate(
        id: 'full_item',
        title: 'Whole item',
        instruction: 'Photograph the whole item on a plain background.',
        why: 'Shows what the item is.',
        guide: CaptureGuideType.generic,
        tips: CaptureTips.fullView,
        checkpointIds: ['brand_marking'],
        basePriority: 4,
        aliases: ['whole', 'full', 'overview'],
      ),
    ],
    checkpoints: [
      SharedCheckpoints.brandMarking,
      Checkpoint(
        id: 'gn_label',
        name: 'Label text',
        group: 'label',
        check: 'Spelling, grammar and consistency of the label text with the brand named.',
        authenticWeight: Weight.low,
        counterfeitWeight: Weight.medium,
        requires: ModelLevel.brand,
      ),
      Checkpoint(
        id: 'gn_print_quality',
        name: 'Print quality',
        group: 'print',
        check: 'Sharpness and alignment of printed or embossed branding.',
        authenticWeight: Weight.low,
        counterfeitWeight: Weight.medium,
        needsFineDetail: true,
        requires: ModelLevel.brand,
      ),
      Checkpoint(
        id: 'gn_construction',
        name: 'Construction',
        group: 'construction',
        check: 'Seams, joins and edges: neat and consistent.',
        authenticWeight: Weight.low,
        counterfeitWeight: Weight.low,
        needsFineDetail: true,
        requires: ModelLevel.brand,
      ),
    ],
    cautions: [
      ...SharedCheckpoints.cautions,
      'No product-specific reference is available for this item. Do not invent model-specific criteria; report only what is visible, and only a clear brand imitation or misspelling may be INCONSISTENT with HIGH reliability.',
    ],
    verificationSteps: [
      "Ask the brand's official store or an authorised retailer to inspect it.",
      'Keep proof of purchase from an authorised seller.',
    ],
  );
}
