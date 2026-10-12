import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class NavItem {
  const NavItem(this.icon, this.activeIcon, this.label);
  final IconData icon;
  final IconData activeIcon;
  final String label;
}

class NavCenterAction {
  const NavCenterAction({required this.icon, required this.onTap, required this.tooltip});
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
}

/// Claundry-style floating bottom bar: a rounded blue capsule hovering above the
/// content with white icons; the active tab grows into a white-glass pill with its
/// label. An optional raised amber action sits in the middle.
class FloatingNavBar extends StatelessWidget {
  const FloatingNavBar({super.key, required this.index, required this.onSelect, required this.items, this.centerAction});
  final int index;
  final ValueChanged<int> onSelect;
  final List<NavItem> items;
  final NavCenterAction? centerAction;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final children = <Widget>[
      for (var i = 0; i < items.length; i++) Expanded(child: _Tab(item: items[i], selected: index == i, onTap: () => onSelect(i))),
    ];
    if (centerAction != null) {
      children.insert(children.length ~/ 2, _CenterButton(action: centerAction!));
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, bottomInset > 0 ? bottomInset : 14),
      child: SizedBox(
        height: 68,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: AppColors.brandGradient,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: AppShadows.nav,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: children),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({required this.item, required this.selected, required this.onTap});
  final NavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: InkResponse(
        onTap: onTap,
        radius: 36,
        highlightShape: BoxShape.rectangle,
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          height: 68,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              padding: EdgeInsets.symmetric(horizontal: selected ? 10 : 6, vertical: 7),
              decoration: BoxDecoration(
                color: selected ? Colors.white.withValues(alpha: 0.20) : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(selected ? item.activeIcon : item.icon,
                      color: selected ? Colors.white : Colors.white.withValues(alpha: 0.72), size: 23),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    child: selected
                        ? Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(item.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w800)),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CenterButton extends StatelessWidget {
  const _CenterButton({required this.action});
  final NavCenterAction action;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      child: Transform.translate(
        offset: const Offset(0, -20),
        child: Center(
          child: Tooltip(
            message: action.tooltip,
            child: Semantics(
              button: true,
              label: action.tooltip,
              child: GestureDetector(
                onTap: action.onTap,
                child: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    gradient: AppColors.goldGradient,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.canvas, width: 5),
                    boxShadow: AppShadows.glow(AppColors.goldDark),
                  ),
                  child: Icon(action.icon, color: AppColors.onGold, size: 28),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
