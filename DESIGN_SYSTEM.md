# Smart-Wash Customer App — Design System

Premium KSA laundry aesthetic. Every screen MUST use these tokens/widgets — no ad-hoc
colors, raw `Card`s, or `CircularProgressIndicator` in page bodies.

## Tokens — `lib/theme/app_theme.dart`
- `AppColors`: `primary` (#0E7C74 teal), `primaryBright`, `primaryDark`, `primarySoft`,
  `gold` (#C6A15B), `goldBright`, `goldDark`, `goldSoft`, `ink`, `inkSoft`, `muted`, `faint`,
  `canvas`, `surface`, `surfaceAlt`, `line`, `lineSoft`, `success`, `warning`, `danger`, `info`.
  Gradients: `AppColors.brandGradient`, `AppColors.goldGradient`.
- `AppRadius`: `card` 22, `control` 14, `chip` 30, `pill` 16, `sheet` 28.
- `AppShadows.soft`, `AppShadows.card`, `AppShadows.glow(color)`.
- Text: use `Theme.of(context).textTheme` — `headlineMedium`/`titleLarge`/`titleMedium`/`bodyMedium`/`labelLarge`.

## Shared widgets — `lib/widgets/ui.dart`
- `money(amount, currency, lang)` → localized currency string.
- `SoftCard(child, {padding, onTap, color})` — the ONE card. White, rounded 22, soft shadow.
- `BrandHero(child, {padding})` — gradient teal header with rounded bottom (screen headers).
- `SectionHeader(title, {actionLabel, onAction})`.
- `InfoRow(icon, label, value, {valueColor, onTap})` — label/value line for detail cards.
- `MoneyRow(label, value, {strong, accent})` — cost-summary line.
- `FilterPill(label, selected, onTap, {count})` — filter chips/tabs.
- `StatusChip(status, {dense})`, `PaymentChip(paymentStatus)`.
- `statusColor(status)`, `statusIcon(status)` — status→visual helpers.
- State views: `LoadingView`, `SkeletonList(count)`, `SkeletonBox(...)`, `ErrorView(msg, {onRetry})`,
  `EmptyView(msg, {icon, hint})`.
- `showToast(context, msg, {error})` — floating snackbar.
- Other widgets: `OrderCard(order, {onTap})`, `JourneyStepper(status, type)`,
  `OrderTimeline(events)`, `QuantityStepper(value, onChanged)`,
  `MapPickerScreen(settings, {initial, initialAddress})` → returns `({LatLng point, String address})`,
  `MapViewer(pickup?, delivery?, height, interactive)`.

## Rules
1. Every visible string wrapped in `context.t('English source')` (Arabic auto-resolves; missing → English).
2. Page background is `AppColors.canvas` (scaffold default). Content padding 20 horizontal.
3. Loading = `SkeletonList` or `LoadingView`; errors = `ErrorView(..., onRetry:)`; empty = `EmptyView`.
4. Buttons come from the theme (ElevatedButton/OutlinedButton) — 56px tall, rounded 14.
5. RTL-safe: use `EdgeInsetsDirectional`/logical properties where practical; never hardcode left/right for text.
6. Premium feel: soft shadows, generous spacing, gradient hero headers, icon-led rows, rounded 14–22.
   Avoid flat gray boxes and cramped layouts.
7. Keep ALL existing business logic / service calls / navigation contracts intact — restyle only.

## Navigation
Bottom nav (home_shell): **Home · Orders · Payments · Account**, with a prominent New-Pickup
action (center FAB or dashboard card). Standalone routes pushed on top: New Order, Order Details,
Map Picker, Notifications, Track, Profile Edit.
