import 'package:flutter/foundation.dart';
import '../models/guide.dart';
import '../models/product.dart';

class GuideRepository extends ChangeNotifier {
  final List<GuideArticle> _guides = [
    const GuideArticle(
      id: 'guide_sneakers',
      title: 'How to Check a Sneaker',
      subtitle: 'Key signals: Toe box curvature, swoosh placement & UV light check',
      category: ProductCategory.sneakers,
      readTimeMinutes: 4,
      difficulty: 'Beginner',
      imageAsset: 'assets/images/sneaker_viewfinder.png',
      summary:
          'Sneaker authentication relies on precise structural geometry, stitching stitch-per-inch density, and font typography on the inner size tag.',
      redFlags: [
        'Overly thick or boxy toe box shape',
        'Inconsistent swoosh tip taper or rounded points',
        'Chemical glue odor upon opening the box',
        'Size tag font thickness that looks stamped rather than printed cleanly',
        'Misaligned midsole star patterns',
      ],
      proTip:
          'Use a 365nm UV blacklight flashlight in a dark room. Authentic shoes typically exhibit no invisible glue markings or unauthorized factory stamps.',
      steps: [
        GuideStep(
          stepNumber: 1,
          title: 'Toe Box & Silhouette',
          description:
              'Examine the height and curvature of the front toe box. Authentic silhouettes curve upward smoothly without abrupt angles or puffiness.',
          imageAsset: 'assets/images/sneaker_viewfinder.png',
          authenticSignal: 'Gentle gradient upward slope with crisp double stitching.',
          replicaSignal: 'Steep vertical rise with bulky sponge padding inside.',
        ),
        GuideStep(
          stepNumber: 2,
          title: 'Logo Placement & Cuts',
          description:
              'Check the lateral Swoosh or brand emblem. The leather cuts should be razor-sharp with no frayed edges or jagged lines.',
          imageAsset: 'assets/images/thumb_nike.png',
          authenticSignal: 'Precise die-cut leather edge with consistent 1mm margin to stitching.',
          replicaSignal: 'Rough, wavy cut with frayed threads and inconsistent margin.',
        ),
        GuideStep(
          stepNumber: 3,
          title: 'Stitching Tension & Count',
          description:
              'Count the stitches along the eyestay and quarter panel. Stitches should be uniform in length, angle, and tension.',
          imageAsset: 'assets/images/watch_bracelet.png',
          authenticSignal: 'Even 8–9 stitches per inch with slight diagonal pitch.',
          replicaSignal: 'Straight loose stitches, frayed thread ends, or double-punched holes.',
        ),
        GuideStep(
          stepNumber: 4,
          title: 'Inner Size Label Typography',
          description:
              'Inspect the dates, barcode, and production codes on the interior tongue tag. Font kerning and UPC bar spacing are rarely replicated perfectly.',
          imageAsset: 'assets/images/bag_production.png',
          authenticSignal: 'Crisp thermal transfer print; thin zeros with standard oval center.',
          replicaSignal: 'Bold, fuzzy text edges with touching numbers or bleeding ink.',
        ),
      ],
    ),
    const GuideArticle(
      id: 'guide_watches',
      title: 'How to Inspect a Luxury Watch',
      subtitle: 'Dial typography, cyclops lens magnification & movement sweep',
      category: ProductCategory.watches,
      readTimeMinutes: 5,
      difficulty: 'Advanced',
      imageAsset: 'assets/images/rolex_thumb.png',
      summary:
          'Swiss horology is defined by micron-level tolerances. Clones and high-end replicas frequently falter on laser engravings, cyclops magnification, and dial typography.',
      redFlags: [
        'Cyclops date window magnification below 2.5x with noticeable reflection',
        'Stuttering second hand (ticks instead of smooth 8-beat per second sweep)',
        'Misaligned laser-etched rehaut coronet at 12 o\'clock',
        'Rough winding action or audible grinding when turning the crown',
        'Loose bracelet end-links with gaps wider than 0.1mm against the case',
      ],
      proTip:
          'Authentic sapphire crystal date lenses feature an anti-reflective coating on the underside, making the date sharply readable from acute angles without glare.',
      steps: [
        GuideStep(
          stepNumber: 1,
          title: 'Dial Text & Font Serif',
          description:
              'Under 10x magnification, inspect the brand wordmark, depth ratings, and chronometer certifications. The paint should be clean without bleeding.',
          imageAsset: 'assets/images/watch_dial.png',
          authenticSignal: 'Crisp raised lacquer print with sharp serifs and consistent kerning.',
          replicaSignal: 'Flat, fuzzy letter contours with filled counters (e.g., inside \'e\' and \'o\').',
        ),
        GuideStep(
          stepNumber: 2,
          title: 'Cyclops Magnification & Date Wheel',
          description:
              'The cyclops lens should magnify the date by exactly 2.5x so the numbers comfortably fill the aperture.',
          imageAsset: 'assets/images/rolex_dial_large.png',
          authenticSignal: 'Date fills aperture neatly; crisp sans-serif typeface with flat top \'3\'.',
          replicaSignal: 'Under-magnified (approx 1.5x) with blueish lens tint and misaligned number.',
        ),
        GuideStep(
          stepNumber: 3,
          title: 'Rehaut Engraving & Coronet',
          description:
              'Inspect the inner bezel ring between the dial and crystal. The serial and repeating brand name must be laser etched with micro-precision.',
          imageAsset: 'assets/images/watch_crown.png',
          authenticSignal: 'Double-line laser etched lettering; Rolex crown aligns dead-center at 12:00.',
          replicaSignal: 'Single-line crude scratch engraving with off-center alignment.',
        ),
        GuideStep(
          stepNumber: 4,
          title: 'Caseback & Clasp Hallmarks',
          description:
              'Examine the milling of the clasp coronet and the model reference stamping between the case lugs.',
          imageAsset: 'assets/images/watch_caseback.png',
          authenticSignal: 'Silky smooth glide-lock mechanism with clean sandblasted crown emblem.',
          replicaSignal: 'Rough clasp friction, sharp unfinished edges, and stamped clasp code.',
        ),
      ],
    ),
    const GuideArticle(
      id: 'guide_bags',
      title: 'How to Inspect a Luxury Bag',
      subtitle: 'Heat stamps, leather grain, hardware engravings & date codes',
      category: ProductCategory.bags,
      readTimeMinutes: 4,
      difficulty: 'Intermediate',
      imageAsset: 'assets/images/thumb_lv.png',
      summary:
          'Authentic designer handbags utilize artisan leather craftsmanship, distinctive stitch angles, and precision hardware casting that replicas struggle to copy.',
      redFlags: [
        'Synthetic chemical polyurethane scent instead of natural tanned leather',
        'Lightweight, hollow metal hardware or plastic zippers painted metallic',
        'Misaligned monogram symmetry across exterior seams',
        'Uneven heat stamping with fluctuating gold foil depth',
        'Bright artificial yellow or plastic-looking edge paint coat',
      ],
      proTip:
          'High-end French fashion houses use traditional two-needle saddle stitching, which angles each stitch at roughly 45 degrees rather than straight machine lines.',
      steps: [
        GuideStep(
          stepNumber: 1,
          title: 'Monogram & Canvas Pattern',
          description:
              'Observe pattern alignment along side seams and the base. Authentic bags maintain balanced symmetry across panels.',
          imageAsset: 'assets/images/bag_logo.png',
          authenticSignal: 'Even horizontal pattern continuity and warm organic canvas hue.',
          replicaSignal: 'Slanted pattern cutoff, muddy print colors, and blurry micro-details.',
        ),
        GuideStep(
          stepNumber: 2,
          title: 'Heat Stamp & Font Proportions',
          description:
              'Inspect the interior brand heat stamp. Pay special attention to the \'O\' (which should be round, not oval in LV) and spacing of \'PARIS\'.',
          imageAsset: 'assets/images/bag_production.png',
          authenticSignal: 'Clean, shallow imprint with sharp circular O\'s and crisp letter spacing.',
          replicaSignal: 'Deep uneven press with gold foil bleeding beyond letter borders.',
        ),
        GuideStep(
          stepNumber: 3,
          title: 'Hardware Weight & Engravings',
          description:
              'Weigh and feel the metal clasps, rivets, and zipper pulls. Authentic hardware is solid brass with polished plating.',
          imageAsset: 'assets/images/bag_hardware.png',
          authenticSignal: 'Substantial cold metallic weight with mirror polish and centered engraving.',
          replicaSignal: 'Lightweight zinc alloy, slight bubbling on plating, shallow laser etching.',
        ),
        GuideStep(
          stepNumber: 4,
          title: 'Edge Paint & Glazing',
          description:
              'Inspect the protective rubberized glaze on handles and leather trims. It should be supple and matte.',
          imageAsset: 'assets/images/bag_stitching.png',
          authenticSignal: 'Smooth, thin, deep burgundy or muted brown coat that flexes naturally.',
          replicaSignal: 'Thick, sticky, bright red paint that cracks when bent.',
        ),
      ],
    ),
    const GuideArticle(
      id: 'guide_stitching',
      title: 'How to Check Stitching & Hardware',
      subtitle: 'Identifying machine replication vs hand-crafted luxury',
      category: ProductCategory.accessories,
      readTimeMinutes: 3,
      difficulty: 'Beginner',
      imageAsset: 'assets/images/watch_bracelet.png',
      summary:
          'Stitching is often the quickest giveaway on counterfeit luxury goods. Learn how to spot improper tension, back-stitches, and fake electroplating.',
      redFlags: [
        'Skipped or crooked stitches along key seams',
        'Uneven stitch length spanning from 2mm to 4mm along the same line',
        'Hardware screws with off-center drive slots or burred metal',
        'Zippers that catch or do not glide smoothly with single finger pull',
      ],
      proTip:
          'Luxury brands coat their linen thread in beeswax before sewing, giving authentic seams a water-resistant, matte finish that never frays.',
      steps: [
        GuideStep(
          stepNumber: 1,
          title: 'Stitch Pitch and Direction',
          description:
              'Check whether stitches slant consistently in the same direction or alternate erratically.',
          imageAsset: 'assets/images/watch_bracelet.png',
          authenticSignal: 'Consistent slant angle across the entirety of every exterior seam.',
          replicaSignal: 'Horizontal straight lines indicative of cheap automated sewing machines.',
        ),
        GuideStep(
          stepNumber: 2,
          title: 'Corner Reinforcement',
          description:
              'Inspect how corners and strap anchors are secured. Luxury makers double-stitch only on designated stress points.',
          imageAsset: 'assets/images/bag_stitching.png',
          authenticSignal: 'Exactly two overlapping stitches tied off seamlessly on the interior.',
          replicaSignal: 'Messy knots, loose loops, or bunched thread clumps.',
        ),
      ],
    ),
    const GuideArticle(
      id: 'guide_replica_signals',
      title: 'Common Replica Signals & Red Flags',
      subtitle: 'Top 5 universal signs a counterfeit product has entered your hands',
      category: ProductCategory.clothing,
      readTimeMinutes: 3,
      difficulty: 'Beginner',
      imageAsset: 'assets/images/mascot_tip.png',
      summary:
          'Regardless of category, almost all counterfeit operations cut corners in the same five areas: packaging, chemical odors, font consistency, hardware alloy, and weight.',
      redFlags: [
        'Packaging with misspelling, washed-out printing, or thin corrugated box walls',
        'Strong solvent, petroleum, or cheap adhesive odor',
        'Disproportionately lightweight feel compared to manufacturer specs',
        'Missing serial numbers or fake QR codes leading to non-official domains',
        'Included certificates of authenticity in cheap laminate (luxury brands rarely issue plastic cards)',
      ],
      proTip:
          'Always verify serial numbers against authentic reference databases and weigh the item on a digital kitchen scale (in grams) against official retail specifications.',
      steps: [
        GuideStep(
          stepNumber: 1,
          title: 'Digital Scale Weight Check',
          description:
              'Compare the exact weight of the item against official specs. Replicas use lighter zinc alloys and hollow links.',
          imageAsset: 'assets/images/watch_caseback.png',
          authenticSignal: 'Matches factory weight within +/- 1.5 grams.',
          replicaSignal: 'Noticeably lighter (often 20–40 grams lighter on luxury watches).',
        ),
        GuideStep(
          stepNumber: 2,
          title: 'Packaging & Accompanying Papers',
          description:
              'Examine the box corners, felt dustbags, and pamphlets. Authentic dustbags are high-thread-count flannel or cotton.',
          imageAsset: 'assets/images/bag_interior.png',
          authenticSignal: 'Heavy linen/cotton dustbag with crisp silkscreening and natural cords.',
          replicaSignal: 'Stiff synthetic polyester dustbag with coarse nylon drawstring.',
        ),
      ],
    ),
  ];

  List<GuideArticle> get allGuides => List.unmodifiable(_guides);
}

