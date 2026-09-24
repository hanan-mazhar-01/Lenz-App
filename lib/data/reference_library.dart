import '../models/product.dart';

class ReferenceFeature {
  final String id;
  final String title;
  final String description;
  final String expectedDetail;
  final bool isCritical;

  const ReferenceFeature({
    required this.id,
    required this.title,
    required this.description,
    required this.expectedDetail,
    this.isCritical = false,
  });
}

class ProductReference {
  final String brand;
  final String model;
  final ProductCategory category;
  final List<ReferenceFeature> features;
  final List<String> commonReplicaFlaws;

  const ProductReference({
    required this.brand,
    required this.model,
    required this.category,
    required this.features,
    required this.commonReplicaFlaws,
  });
}

class ReferenceLibrary {
  static const List<ProductReference> references = [
    ProductReference(
      brand: 'Rolex',
      model: 'Submariner',
      category: ProductCategory.watches,
      features: [
        ReferenceFeature(
          id: 'dial',
          title: 'Dial & Typography',
          description: 'Pad printed text with sharp serifs and consistent kerning.',
          expectedDetail: 'Crisp ROLEX coronet with oval opening at base; "SWISS MADE" with small coronet at 6:00; no bleeding on text.',
          isCritical: true,
        ),
        ReferenceFeature(
          id: 'crown',
          title: 'Triplock Crown & Guards',
          description: 'Screw-down crown with rubber O-ring gasket system.',
          expectedDetail: 'Coronet above three small dots (triplock); precise machine knurling without casting burrs; crown guards blend smoothly into mid-case.',
          isCritical: true,
        ),
        ReferenceFeature(
          id: 'caseback',
          title: 'Caseback & Fluting',
          description: 'Oyster caseback with specific fluting tool teeth.',
          expectedDetail: 'Flat brushed circular satin finish; strictly no exterior engravings on standard Submariners; perfectly uniform teeth around circumference.',
          isCritical: true,
        ),
        ReferenceFeature(
          id: 'rehaut',
          title: 'Engraved Rehaut',
          description: 'Laser-etched inner bezel ring under crystal.',
          expectedDetail: '"ROLEX" repeated; "X" aligned exactly with hour markers on right (1-5), "R" aligned with markers on left (7-11); coronet at 12:00; serial at 6:00.',
          isCritical: true,
        ),
        ReferenceFeature(
          id: 'bracelet_clasp',
          title: 'Oyster Bracelet & Glidelock',
          description: 'Solid 904L / Oystersteel links and clasp mechanism.',
          expectedDetail: 'Solid end links with zero wobble or gap against case lugs; Glidelock tooth track milled smooth with crisp spring latching.',
          isCritical: false,
        ),
      ],
      commonReplicaFlaws: [
        'Wrong font weight or fuzzy serif edges on dial printing',
        'Misaligned rehaut engravings relative to minute markers',
        'Laser-etched caseback engravings where genuine is sterile brushed',
        'Uneven or rough machine teeth on caseback coin edge',
        'Rough cyclops magnification (less than 2.5x) or missing anti-reflective coating',
      ],
    ),
    ProductReference(
      brand: 'Apple',
      model: 'Apple Watch Ultra',
      category: ProductCategory.watches,
      features: [
        ReferenceFeature(
          id: 'case_materials',
          title: 'Titanium Enclosure & Sapphire',
          description: 'Aerospace-grade matte titanium chassis with raised bezel.',
          expectedDetail: 'Bezel lip rises around flat sapphire front crystal; fine bead-blasted satin matte finish; distinct chamfered edge.',
          isCritical: true,
        ),
        ReferenceFeature(
          id: 'action_button_crown',
          title: 'Action Button & Digital Crown',
          description: 'Tactile high-contrast international orange button and rugged crown guard.',
          expectedDetail: 'Orange anodized aluminum action button with tactile click; deep grooved digital crown with orange ring and dual mic holes.',
          isCritical: true,
        ),
        ReferenceFeature(
          id: 'caseback_sensors',
          title: 'Ceramic Caseback & Sensors',
          description: 'Zirconia ceramic back with recessed sensor cluster.',
          expectedDetail: 'Concentric text laser-etched with ultra-fine precision; 4 corner pentalobe screws flush with case; optical crystal sensors.',
          isCritical: true,
        ),
        ReferenceFeature(
          id: 'lug_attachment',
          title: 'Band Pushers & Retention',
          description: 'Internal spring-loaded latch pushers.',
          expectedDetail: 'Top and bottom central pushers press smoothly with internal spring tension; secure band click with zero lateral wobble.',
          isCritical: false,
        ),
      ],
      commonReplicaFlaws: [
        'Plastic or zinc alloy chassis painted silver instead of genuine titanium',
        'Curved front glass instead of recessed flat sapphire',
        'Screen bezel too thick with lower resolution LCD instead of borderless OLED',
        'Fake sensor LEDs or painted plastic back without pentalobe screws',
      ],
    ),
    ProductReference(
      brand: 'Louis Vuitton',
      model: 'Neverfull',
      category: ProductCategory.bags,
      features: [
        ReferenceFeature(
          id: 'monogram_canvas',
          title: 'Monogram Alignment & Quality',
          description: 'Coated canvas with classic Monogram pattern.',
          expectedDetail: 'Continuous piece of coated canvas (upside down on reverse side); symmetrical floral motifs centered horizontally and vertically.',
          isCritical: true,
        ),
        ReferenceFeature(
          id: 'stitching_glazing',
          title: 'Stitching & Edge Glazing',
          description: 'Yellow mustard linen thread and deep red edge coating.',
          expectedDetail: 'Slightly angled stitch lines with identical stitch counts on symmetrical tabs; smooth dark reddish-brown edge paint without sticky residue.',
          isCritical: true,
        ),
        ReferenceFeature(
          id: 'hardware',
          title: 'Brass Hardware & Engravings',
          description: 'Solid brass metal fittings and D-rings.',
          expectedDetail: 'Golden brass with weight; crisp "LOUIS VUITTON" font stamping with circular "O" and straight leg on "R".',
          isCritical: false,
        ),
      ],
      commonReplicaFlaws: [
        'Bright neon red glazing on handle edges',
        'Crooked or cut-off monogram motifs at visible top border seams',
        'Thin plastic-feeling canvas with excessive synthetic chemical smell',
        'Lightweight plated alloy hardware that chips easily',
      ],
    ),
    ProductReference(
      brand: 'Nike',
      model: 'Air Jordan 4',
      category: ProductCategory.sneakers,
      features: [
        ReferenceFeature(
          id: 'silhouette_toebox',
          title: 'Silhouette & Toe Box Curvature',
          description: 'Streamlined profile and curved mudguard contour.',
          expectedDetail: 'Low-profile toe box with upward slope; hourglass shape from rear heel view.',
          isCritical: true,
        ),
        ReferenceFeature(
          id: 'netting',
          title: 'Side & Tongue Netting',
          description: 'Angled TPU mesh netting.',
          expectedDetail: 'Netting flows parallel to the eyestay angles; soft flexible urethane material.',
          isCritical: true,
        ),
        ReferenceFeature(
          id: 'heel_tab',
          title: 'Heel Tab & Waffle Eyelets',
          description: 'Molded plastic waffle wings and heel pull tab.',
          expectedDetail: 'Nine crisp eyelet holes per wing; heel tab snaps back firmly when bent downward; Jumpman/Nike Air placement centered.',
          isCritical: false,
        ),
      ],
      commonReplicaFlaws: [
        'Netting runs straight horizontal/vertical instead of angled',
        'Bulky, boxy toe box shape',
        'Slow rebound or flimsy rubber on heel tab',
      ],
    ),
  ];

  /// Finds matching reference for brand and product/model
  static ProductReference? findReference(String brand, String productOrModel) {
    final bLower = brand.toLowerCase();
    final pLower = productOrModel.toLowerCase();

    for (final ref in references) {
      if (bLower.contains(ref.brand.toLowerCase()) || ref.brand.toLowerCase().contains(bLower)) {
        if (pLower.contains(ref.model.toLowerCase()) || ref.model.toLowerCase().contains(pLower)) {
          return ref;
        }
      }
    }

    // Fallback brand match if model is vague
    for (final ref in references) {
      if (bLower.contains(ref.brand.toLowerCase()) || ref.brand.toLowerCase().contains(bLower)) {
        return ref;
      }
    }

    return null;
  }
}

