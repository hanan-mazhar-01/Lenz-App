import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../services/haptics.dart';

class IosBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const IosBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
        child: Container(
          height: 64,
          decoration: BoxDecoration(
            color: AppColors.veryLightWarmGray,
            borderRadius: BorderRadius.circular(34),
            border: Border.all(
              color: AppColors.nearBlack.withOpacity(0.14),
              width: 0.8,
            ),
            boxShadow: const [
              BoxShadow(
                color: AppColors.shadowMedium,
                blurRadius: 20,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildNavItem(
                index: 0,
                icon: CupertinoIcons.house,
                activeIcon: CupertinoIcons.house_fill,
                label: 'Home',
              ),
              _buildNavItem(
                index: 1,
                icon: CupertinoIcons.camera,
                activeIcon: CupertinoIcons.camera_fill,
                label: 'Scan',
              ),
              _buildNavItem(
                index: 2,
                icon: CupertinoIcons.clock,
                activeIcon: CupertinoIcons.clock_fill,
                label: 'History',
              ),
              _buildNavItem(
                index: 3,
                icon: CupertinoIcons.heart,
                activeIcon: CupertinoIcons.heart_fill,
                label: 'Favorites',
              ),
              _buildNavItem(
                index: 4,
                icon: CupertinoIcons.person,
                activeIcon: CupertinoIcons.person_fill,
                label: 'Profile',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required int index,
    required IconData icon,
    required IconData activeIcon,
    required String label,
  }) {
    final isSelected = currentIndex == index;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          Haptics.selectionClick();
          onTap(index);
        },
        child: SizedBox.expand(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isSelected ? activeIcon : icon,
                size: 21,
                color: isSelected ? AppColors.deepForestGreen : AppColors.softGray,
              ),
              const SizedBox(height: 3),
              Text(
                label,
                style: AppTypography.caption.copyWith(
                  fontSize: 10.5,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? AppColors.deepForestGreen : AppColors.softGray,
                ),
              ),
              const SizedBox(height: 2),
              // Active underline indicator
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: isSelected ? 16 : 0,
                height: 2.2,
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.deepForestGreen : Colors.transparent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
