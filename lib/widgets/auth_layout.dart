import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'ui.dart';

/// Shared Claundry-style layout for the sign-in family of screens: a soft blue wash
/// at the top with the brand mark, a big friendly title + subtitle, then the form on
/// a clean surface. Optional back button and a footer pinned under the content.
class AuthLayout extends StatelessWidget {
  const AuthLayout({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.subtitleWidget,
    this.showBack = false,
    this.footer,
    this.showLogo = true,
    this.headerIcon,
    this.backEnabled = true,
  });

  final String title;
  final String? subtitle;

  /// Replaces [subtitle] when richer content is needed (e.g. business name chip).
  final Widget? subtitleWidget;
  final Widget child;
  final bool showBack;
  final Widget? footer;
  final bool showLogo;

  /// Shown instead of the brand logo (e.g. a lock for password reset).
  final IconData? headerIcon;

  /// False disables the back button (e.g. while a request is in flight).
  final bool backEnabled;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final topInset = MediaQuery.paddingOf(context).top;

    final Widget mark = headerIcon != null
        ? Icon(headerIcon, color: AppColors.primary, size: 34)
        : (app.hasLogo
            ? Image.network(app.tenantLogoUrl!,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => Image.asset('assets/brand/smartwash-mark.png', fit: BoxFit.contain))
            : Image.asset('assets/brand/smartwash-mark.png', fit: BoxFit.contain));

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Stack(
        children: [
          // Soft blue wash + rings behind the header.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: topInset + 250,
            child: DecoratedBox(
              // Fades into the page surface so there is no seam under the header in either theme.
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [AppColors.washGradient.colors.first, AppColors.surface],
                ),
              ),
              child: Stack(children: [
                PositionedDirectional(end: -70, top: -60, child: _ring(220)),
                PositionedDirectional(start: -50, top: topInset + 120, child: _ring(120)),
              ]),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 8, 22, 24),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight - 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        height: 48,
                        child: Row(children: [
                          if (showBack)
                            SquareIconButton(
                              icon: Directionality.of(context) == TextDirection.rtl
                                  ? Icons.arrow_forward_rounded
                                  : Icons.arrow_back_rounded,
                              onTap: backEnabled ? () => Navigator.of(context).maybePop() : null,
                            ),
                        ]),
                      ),
                      const SizedBox(height: 8),
                      if (showLogo)
                        Center(
                          child: Container(
                            width: 78,
                            height: 78,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: AppShadows.card,
                            ),
                            child: mark,
                          ),
                        ),
                      const SizedBox(height: 22),
                      Text(title,
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 27, fontWeight: FontWeight.w900, letterSpacing: -0.6, color: AppColors.ink)),
                      const SizedBox(height: 8),
                      if (subtitleWidget != null)
                        Center(child: subtitleWidget!)
                      else if (subtitle != null)
                        Text(subtitle!,
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 14, color: AppColors.muted, height: 1.4)),
                      const SizedBox(height: 28),
                      child,
                      if (footer != null) ...[const SizedBox(height: 18), footer!],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _ring(double size) => IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.07), width: 18),
          ),
        ),
      );
}

/// "Question? Action" text row used under auth forms.
class AuthSwitchRow extends StatelessWidget {
  const AuthSwitchRow({super.key, required this.question, required this.action, required this.onTap});
  final String question;
  final String action;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(question, style: TextStyle(color: AppColors.muted, fontSize: 14)),
        TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6), minimumSize: const Size(44, 40)),
          child: Text(action, style: const TextStyle(fontWeight: FontWeight.w800)),
        ),
      ],
    );
  }
}
