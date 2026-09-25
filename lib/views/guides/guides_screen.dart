import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../models/guide.dart';
import '../../models/product.dart';
import '../../repositories/guide_repository.dart';
import '../../widgets/animations/bounce_button.dart';
import '../../widgets/animations/fade_slide_transition.dart';
import '../../widgets/cards/glass_card.dart';
import '../../widgets/mascot/detective_mascot_widget.dart';
import 'guide_detail_view.dart';

class GuidesScreen extends StatefulWidget {
  final VoidCallback onBack;

  const GuidesScreen({super.key, required this.onBack});

  @override
  State<GuidesScreen> createState() => _GuidesScreenState();
}

class _GuidesScreenState extends State<GuidesScreen> {
  final TextEditingController _searchController = TextEditingController();
  ProductCategory? _selectedCategory;
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openGuide(GuideArticle guide) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GuideDetailView(
          guide: guide,
          onBack: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final guideRepo = context.watch<GuideRepository>();
    List<GuideArticle> guides = guideRepo.allGuides;

    if (_selectedCategory != null) {
      guides = guides.where((g) => g.category == _selectedCategory).toList();
    }
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      guides = guides.where((g) {
        return g.title.toLowerCase().contains(query) ||
            g.subtitle.toLowerCase().contains(query) ||
            g.summary.toLowerCase().contains(query);
      }).toList();
    }

    final featuredGuide = guideRepo.allGuides.isNotEmpty ? guideRepo.allGuides[1] : null; // Rolex guide

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),

              // Header Bar
              Row(
                children: [
                  IconButton(
                    icon: const Icon(CupertinoIcons.chevron_back, color: AppColors.textPrimary),
                    onPressed: widget.onBack,
                  ),
                  Expanded(
                    child: Text(
                      'Authentication Guides',
                      style: AppTypography.displayMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Text(
                  'Expert tips and physical inspection signals.',
                  style: AppTypography.bodyMedium,
                ),
              ),

              const SizedBox(height: 16),

              // Search Box
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [
                    BoxShadow(
                      color: AppColors.shadow,
                      blurRadius: 10,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: TextField(
                  controller: _searchController,
                  onChanged: (val) => setState(() => _searchQuery = val),
                  decoration: InputDecoration(
                    hintText: 'Search guides, red flags, stitching...',
                    hintStyle: AppTypography.bodyMedium.copyWith(color: AppColors.textTertiary),
                    prefixIcon: const Icon(CupertinoIcons.search, color: AppColors.textTertiary, size: 20),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(CupertinoIcons.clear_circled_solid, size: 18, color: AppColors.textTertiary),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Category Filter Chips
              SizedBox(
                height: 38,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  children: [
                    _buildCategoryChip(null, 'All'),
                    ...ProductCategory.values.map((cat) => _buildCategoryChip(cat, cat.label)),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Featured Hero Card (if not searching)
              if (_searchQuery.isEmpty && _selectedCategory == null && featuredGuide != null) ...[
                FadeSlideTransition(
                  delay: const Duration(milliseconds: 100),
                  child: BounceButton(
                    onTap: () => _openGuide(featuredGuide),
                    child: GlassCard(
                      padding: const EdgeInsets.all(18),
                      borderRadius: 24,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppColors.accentSoft,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  'FEATURED SPOTLIGHT',
                                  style: TextStyle(
                                    color: AppColors.accent,
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                              const Spacer(),
                              Text(
                                '${featuredGuide.readTimeMinutes} min read',
                                style: AppTypography.caption,
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      featuredGuide.title,
                                      style: AppTypography.titleLarge,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      featuredGuide.subtitle,
                                      style: AppTypography.caption,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Expanded(
                                flex: 1,
                                child: DetectiveMascotWidget(
                                  size: 68,
                                  state: MascotState.inspecting,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Text(
                                'Read Guide →',
                                style: AppTypography.captionMedium.copyWith(
                                  color: AppColors.accent,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],

              // All Guides Header
              Text(
                _selectedCategory != null
                    ? '${_selectedCategory!.label.toUpperCase()} GUIDES (${guides.length})'
                    : 'ALL GUIDES (${guides.length})',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 12),

              // Guides List
              if (guides.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Column(
                      children: [
                        const Icon(CupertinoIcons.search, size: 44, color: AppColors.textTertiary),
                        const SizedBox(height: 12),
                        Text(
                          'No guides found for "$_searchQuery"',
                          style: AppTypography.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                )
              else
                ...List.generate(guides.length, (i) {
                  final guide = guides[i];
                  return FadeSlideTransition(
                    delay: Duration(milliseconds: 80 + (i * 40)),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: BounceButton(
                        onTap: () => _openGuide(guide),
                        child: GlassCard(
                          padding: const EdgeInsets.all(14),
                          borderRadius: 18,
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  width: 52,
                                  height: 52,
                                  color: AppColors.surface,
                                  child: Image.asset(
                                    guide.imageAsset,
                                    fit: BoxFit.contain,
                                    errorBuilder: (_, __, ___) => Container(
                                      color: AppColors.neutralPill,
                                      child: const Icon(CupertinoIcons.book, color: AppColors.textTertiary),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: AppColors.neutralPill,
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            guide.category.label,
                                            style: const TextStyle(
                                              fontSize: 9.5,
                                              fontWeight: FontWeight.w600,
                                              color: AppColors.textSecondary,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          '${guide.readTimeMinutes} min',
                                          style: AppTypography.caption.copyWith(fontSize: 10.5),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      guide.title,
                                      style: AppTypography.titleMedium.copyWith(fontSize: 14.5),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      guide.subtitle,
                                      style: AppTypography.caption,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(CupertinoIcons.chevron_forward, size: 16, color: AppColors.textTertiary),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }),

              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryChip(ProductCategory? cat, String label) {
    final isSelected = _selectedCategory == cat;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => setState(() => _selectedCategory = cat),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.buttonDark : AppColors.surface,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: isSelected ? AppColors.shadowMedium : AppColors.shadow,
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              color: isSelected ? Colors.white : AppColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

