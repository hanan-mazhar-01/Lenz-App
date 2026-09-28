/// How firmly a product attribute (brand, model, generation...) is known.
enum AttributeStatus {
  /// Established by a readable marking, the device's own information
  /// screen, or a design feature that exists on this model only.
  confirmed('CONFIRMED', 'Confirmed'),

  /// Strongly suggested by the design, but another model could look alike.
  probable('PROBABLE', 'Probable'),

  /// Not established. Nothing model-specific may be judged against it.
  unknown('UNKNOWN', 'Not established');

  final String code;
  final String label;
  const AttributeStatus(this.code, this.label);

  static AttributeStatus parse(String? raw) {
    final s = (raw ?? '').toUpperCase().trim();
    if (s.startsWith('CONFIRM')) return AttributeStatus.confirmed;
    if (s.startsWith('PROBAB') || s.startsWith('LIKELY')) return AttributeStatus.probable;
    return AttributeStatus.unknown;
  }

  bool atLeast(AttributeStatus other) => index <= other.index;
}

/// Where an identity attribute came from.
enum IdentitySource {
  /// Printed or engraved text on the item (label, engraving, size tag).
  marking('MARKING'),

  /// The overall design. Replicas copy designs, so this identifies what an
  /// item is made to look like, never that it is genuine.
  design('DESIGN'),

  /// Shown by the device's own software (e.g. Settings > About). Reported by
  /// the device, not verified with the manufacturer.
  deviceReported('DEVICE_REPORTED'),

  none('NONE');

  final String code;
  const IdentitySource(this.code);

  static IdentitySource parse(String? raw) {
    final s = (raw ?? '').toUpperCase().trim();
    for (final v in values) {
      if (v.code == s) return v;
    }
    if (s.contains('DEVICE') || s.contains('SOFTWARE') || s.contains('SCREEN')) return IdentitySource.deviceReported;
    if (s.contains('MARK') || s.contains('TEXT') || s.contains('ENGRAV') || s.contains('LABEL')) return IdentitySource.marking;
    if (s.contains('DESIGN') || s.contains('SHAPE')) return IdentitySource.design;
    return IdentitySource.none;
  }
}

class IdentityAttribute {
  final String? value;
  final AttributeStatus status;

  /// The visible feature that established it, in plain words.
  final String basis;
  final IdentitySource source;

  const IdentityAttribute({
    this.value,
    this.status = AttributeStatus.unknown,
    this.basis = '',
    this.source = IdentitySource.none,
  });

  static const unknown = IdentityAttribute();

  bool get isKnown => status != AttributeStatus.unknown && (value?.trim().isNotEmpty ?? false);

  static const _placeholders = {
    'null', 'none', 'unknown', 'not_identifiable', 'not identifiable', 'n/a', 'na', 'unclear', '-',
  };

  factory IdentityAttribute.fromParts(dynamic value, dynamic status, {dynamic basis, dynamic source}) {
    final v = value?.toString().trim();
    final clean = (v == null || v.isEmpty || _placeholders.contains(v.toLowerCase())) ? null : v;
    var st = AttributeStatus.parse(status?.toString());
    // A status without a value means nothing, and a value the model did not
    // grade is treated as probable at most: never silently confirmed.
    if (clean == null) st = AttributeStatus.unknown;
    if (clean != null && status == null) st = AttributeStatus.probable;
    return IdentityAttribute(
      value: clean,
      status: st,
      basis: basis?.toString().trim() ?? '',
      source: IdentitySource.parse(source?.toString()),
    );
  }

  Map<String, dynamic> toJson() => {
        'value': value,
        'status': status.code,
        'basis': basis,
        'source': source.code,
      };

  factory IdentityAttribute.fromJson(Map<String, dynamic>? json) {
    if (json == null) return IdentityAttribute.unknown;
    return IdentityAttribute(
      value: json['value'] as String?,
      status: AttributeStatus.parse(json['status'] as String?),
      basis: json['basis'] as String? ?? '',
      source: IdentitySource.parse(json['source'] as String?),
    );
  }

  /// Keeps whichever attribute is established more firmly. On equal
  /// strength the existing value stays, so later photos cannot silently
  /// rename a product.
  IdentityAttribute strongest(IdentityAttribute other) {
    if (!other.isKnown) return this;
    if (!isKnown) return other;
    return other.status.index < status.index ? other : this;
  }

  bool conflictsWith(IdentityAttribute other) {
    if (!isKnown || !other.isKnown) return false;
    if (status == AttributeStatus.unknown || other.status == AttributeStatus.unknown) return false;
    final a = _norm(value!), b = _norm(other.value!);
    if (a.isEmpty || b.isEmpty) return false;
    return !(a.contains(b) || b.contains(a));
  }

  static String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
}

/// Everything known about what the product is, with explicit certainty per
/// attribute. Nothing here says anything about authenticity.
class ProductIdentity {
  final String categoryCode;

  /// Short noun for what the object is, e.g. "smartwatch", "mechanical
  /// watch", "sneaker", "eau de toilette", "wireless earbuds".
  final String productType;
  final IdentityAttribute brand;

  /// E.g. "Apple Watch Ultra", "Submariner", "Air Jordan 4".
  final IdentityAttribute modelFamily;

  /// E.g. "Ultra 2", "Series 9", "126610LN" generation.
  final IdentityAttribute generation;

  /// Reference / model number / style code, when read off the item.
  final IdentityAttribute exactModel;

  final List<String> visibleCharacteristics;
  final List<String> distinguishingFeatures;
  final List<String> uncertainAttributes;

  /// Identity disagreements between photos (e.g. the About screen names a
  /// different model than the case markings).
  final List<String> conflicts;

  const ProductIdentity({
    required this.categoryCode,
    this.productType = '',
    this.brand = IdentityAttribute.unknown,
    this.modelFamily = IdentityAttribute.unknown,
    this.generation = IdentityAttribute.unknown,
    this.exactModel = IdentityAttribute.unknown,
    this.visibleCharacteristics = const [],
    this.distinguishingFeatures = const [],
    this.uncertainAttributes = const [],
    this.conflicts = const [],
  });

  /// Text used to match evidence profiles and references.
  String get searchText => [productType, brand.value, modelFamily.value, generation.value, exactModel.value]
      .whereType<String>()
      .join(' ')
      .toLowerCase();

  /// The model the evidence is compared against, stated with its certainty,
  /// e.g. "Apple Watch Ultra (generation not established)". Generation notes
  /// are only added when [mentionGeneration] is set (products with
  /// generation-specific checks).
  String evaluatedModelLabel({bool mentionGeneration = false}) {
    final b = brand.value?.trim() ?? '';
    final fam = modelFamily.value?.trim() ?? '';
    final gen = generation.value?.trim() ?? '';
    var name = fam.isEmpty
        ? b
        : (b.isEmpty || fam.toLowerCase().contains(b.toLowerCase()) ? fam : '$b $fam');
    if (name.isEmpty) return 'unidentified item';
    if (gen.isNotEmpty && !name.toLowerCase().contains(gen.toLowerCase())) {
      // "Apple Watch Ultra" + "Ultra 2" -> "Apple Watch Ultra 2";
      // "Apple Watch Series" + "Series 9" -> "Apple Watch Series 9".
      final lastWord = name.split(' ').last.toLowerCase();
      final genWords = gen.split(' ');
      name = genWords.length > 1 && genWords.first.toLowerCase() == lastWord
          ? '$name ${genWords.sublist(1).join(' ')}'
          : '$name $gen';
    }
    final notes = <String>[];
    if (fam.isEmpty) {
      notes.add('model not established');
    } else if (modelFamily.status == AttributeStatus.probable) {
      notes.add('model probable');
    }
    if (mentionGeneration && fam.isNotEmpty) {
      if (generation.status == AttributeStatus.unknown) {
        notes.add('generation not established');
      } else if (generation.status == AttributeStatus.probable) {
        notes.add('generation probable');
      }
    }
    return notes.isEmpty ? name : '$name (${notes.join(', ')})';
  }

  /// Merges identity information revealed by a later photo.
  ProductIdentity mergedWith({
    IdentityAttribute? brand,
    IdentityAttribute? modelFamily,
    IdentityAttribute? generation,
    IdentityAttribute? exactModel,
    String? sourceLabel,
  }) {
    final newConflicts = <String>[...conflicts];
    void check(String what, IdentityAttribute current, IdentityAttribute? incoming) {
      if (incoming == null) return;
      if (current.conflictsWith(incoming)) {
        final note = '$what: "${current.value}" (${current.basis.isEmpty ? current.source.code.toLowerCase() : current.basis}) '
            'vs "${incoming.value}"${sourceLabel == null ? '' : ' ($sourceLabel)'}';
        if (!newConflicts.contains(note)) newConflicts.add(note);
      }
    }

    check('Brand', this.brand, brand);
    check('Model', this.modelFamily, modelFamily);
    check('Generation', this.generation, generation);
    check('Model number', this.exactModel, exactModel);

    return ProductIdentity(
      categoryCode: categoryCode,
      productType: productType,
      brand: brand == null ? this.brand : this.brand.strongest(brand),
      modelFamily: modelFamily == null ? this.modelFamily : this.modelFamily.strongest(modelFamily),
      generation: generation == null ? this.generation : this.generation.strongest(generation),
      exactModel: exactModel == null ? this.exactModel : this.exactModel.strongest(exactModel),
      visibleCharacteristics: visibleCharacteristics,
      distinguishingFeatures: distinguishingFeatures,
      uncertainAttributes: uncertainAttributes,
      conflicts: newConflicts,
    );
  }

  Map<String, dynamic> toJson() => {
        'category_code': categoryCode,
        'product_type': productType,
        'brand': brand.toJson(),
        'model_family': modelFamily.toJson(),
        'generation': generation.toJson(),
        'exact_model': exactModel.toJson(),
        'visible_characteristics': visibleCharacteristics,
        'distinguishing_features': distinguishingFeatures,
        'uncertain_attributes': uncertainAttributes,
        'conflicts': conflicts,
      };

  factory ProductIdentity.fromJson(Map<String, dynamic> json) {
    List<String> strings(String k) => (json[k] as List?)?.map((e) => e.toString()).toList() ?? const [];
    Map<String, dynamic>? m(String k) => json[k] is Map ? Map<String, dynamic>.from(json[k] as Map) : null;
    return ProductIdentity(
      categoryCode: json['category_code'] as String? ?? 'OTHER',
      productType: json['product_type'] as String? ?? '',
      brand: IdentityAttribute.fromJson(m('brand')),
      modelFamily: IdentityAttribute.fromJson(m('model_family')),
      generation: IdentityAttribute.fromJson(m('generation')),
      exactModel: IdentityAttribute.fromJson(m('exact_model')),
      visibleCharacteristics: strings('visible_characteristics'),
      distinguishingFeatures: strings('distinguishing_features'),
      uncertainAttributes: strings('uncertain_attributes'),
      conflicts: strings('conflicts'),
    );
  }
}
