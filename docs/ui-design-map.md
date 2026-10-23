# Artha UI redesign — design map from the reference mock

Source: five-screen mobile finance mock (clipboard capture, 1181×883 @1x). Colours below were
sampled from the pixels of that image, not eyeballed. This document is the contract the redesign
in `lib/ui/theme.dart`, `lib/ui/components.dart` and the finance pages implement.

## 1. Design language in one paragraph

Flat, paper-soft fintech. A warm-neutral grey canvas carries borderless white cards with generous
radii; there are no shadows and no outlines — separation comes from background contrast alone.
One saturated indigo (`#2C1CD1`) is the only loud colour, used for icons, chart lines, badges and
small fills; a deeper blue (`#0000C6`) is reserved for hero fills (feature card, celebration
banner); a pale sky (`#C8E6FE`) tints icon squares, highlighted rows and progress tracks. Type is
Inter: heavy (700) for every number and heading, medium (500–600) for labels, grey (`#8A8A8A`)
for anything secondary. Numbers are tabular. Corners: 20 on cards, 14–16 on inner tiles and
inputs, 999 on pills and circular buttons.

## 2. Tokens

### 2.1 Colour (light, "Indigo Paper" — sampled)

| Token            | Hex       | Sampled from                                   |
|------------------|-----------|------------------------------------------------|
| canvas           | `#F2F2F2` | page background behind cards                   |
| surface (card)   | `#FFFFFF` | every card                                     |
| surfaceSoft      | `#F7F7F7` | inner tiles, input fill, avatar discs          |
| ink              | `#0A0A0A` | headings, amounts, selected nav (`#010101`)    |
| muted            | `#8A8A8A` | secondary lines, captions, unselected nav grey |
| faint            | `#B9B9B9` | axis labels, placeholders                      |
| hairline / track | `#E4E4E4` | progress tracks, dividers (`#DEDEDE`–`#E0E0E0`)|
| primary          | `#2C1CD1` | icon glyphs, chart line, badges, progress fill |
| primaryDeep      | `#0000C6` | feature card fill, celebration banner          |
| soft             | `#C8E6FE` | icon-square tint, highlighted row, track fill  |
| onSoft           | `#2C1CD1` | glyph on soft                                  |
| income good      | `#0B7A3E` | kept from core (signed income amounts)         |

Dark variant ("Indigo Night") mirrors the same roles: canvas `#121212`, surface `#1C1C1F`,
surfaceSoft `#242428`, ink `#F4F4F5`, muted `#9A9AA2`, track `#2E2E33`, primary `#6E5BFF`,
primaryDeep `#3B2BD6`, soft `#12344F`, onSoft `#8FC7F2`.

### 2.2 Type (Inter, tabular figures for all money)

| Role             | Size / weight | Notes                                  |
|------------------|---------------|----------------------------------------|
| page title       | 28 / 700      | app bar, left aligned, -0.5 tracking   |
| hero line        | 28 / 700      | line 1 ink, line 2 muted               |
| card big number  | 28–34 / 700   | net worth, savings, balances           |
| section header   | 16 / 700      | "Your Activity", "Accounts"            |
| see-all link     | 13 / 500      | muted, right of section header         |
| card label       | 13 / 600      | muted ("Total Spend", "Income")        |
| body / row title | 14 / 600      | payee, account name                    |
| caption          | 12 / 500      | muted subtitles, statuses              |
| nav label        | 11 / 600      | selected ink, unselected `#B9B9B9`     |
| axis / badge sm  | 10–11 / 500   | chart axes, pill badge 11/700 white    |

### 2.3 Shape, space, elevation

- Radii: card 20, inner tile 16, icon square 14, input 14, dialog & sheet 24, pill 999, badge 10.
- Padding: page 16, card 16–20, tile 16; grid gap 12; section gap 24; row height 56–64.
- Elevation: none anywhere. No borders except 1 px hairline `#ECECEC` where lists need dividing.
- Icon squares 44–48, radius 14; avatar discs 40, radius 999, fill surfaceSoft, initials 12/600.
- Circular buttons 40: solid ink with white glyph (primary action), solid surface with ink glyph.

### 2.4 Charts

- Horizontal grid: 1 px dashed `#E4E4E4`, no vertical grid, no axis border.
- Primary series: 2 px round-cap line in `primary`, 10 % alpha area fill below.
- Comparison series: 2 px line in mid-sky `#7FB8E8`.
- Selected point: dashed vertical line in `primary`, ring dot, and a pill badge above
  (fill `primary`, radius 10, white 11/700 tabular text).
- Bars: `primary` and `soft`-derived second colour, top radius 4, width 7–12.

## 3. Components

1. **PageHeader** — title left (28/700); right: circular ink "+" and circular surface action.
2. **HeroHeader** — two 28/700 lines, ink then muted ("You are on Top / of your Finances").
3. **StatTile** — white r16, pad 16: label 13/600 muted + trailing arrow icon 16; value 20/700.
4. **ChartCard** — white r20, pad 16: label 13/600 muted, number 28/700, chart 150–240 high.
5. **SectionHeader** — 16/700 ink left, "See all" 13/500 muted right, 12 above content.
6. **ActivityCard** — white r20, pad 16: overlapping 32 discs or text with indigo-bold span,
   caption 12/500 muted, value 18/700.
7. **AccountTile** — white r20, pad 16: icon square 48 r14 (soft+primary or primary+white,
   alternating), name 14/600, balance 12/500 muted.
8. **TxRow** — inside white r20 card under a muted date caption: disc avatar with initials,
   title 14/600 + sub 12/500 muted, trailing amount 14/700 (signed) over status 11/500 muted.
9. **StackCard / FeatureCard** — stacked r16 rows (white, soft-highlighted) over a primaryDeep
   r20 card: white 14/700 name, 12/600 tag, 40/700 centred amount, footer status row 12/600.
10. **ProgressCard** — white r20: label rows, mini bar 64×6 r3 (track soft, fill primary),
    big number 34/700, "out of …" 12/500 muted, slider track 8 r4 soft with primary dots.
11. **BannerPill** — primaryDeep r12, pad 12×16: white 12/600 message left, streak right.
12. **StatsCard** — white r20, pad 16: icon disc 40 (soft or primary), title 14/700,
    caption 11/500 muted.
13. **BottomNav / Rail** — white bar, 4–5 items, selected ink icon+label, others `#B9B9B9`;
    desktop rail on canvas with soft r12 indicator and primary selected icon.

## 4. Screen inventory (mock)

- **S1 Finance**: PageHeader → HeroHeader → ChartCard(Total Spend) → 2×StatTile(Income,
  Expenses) → SectionHeader(Your Activity) → 2×ActivityCard → BottomNav.
- **S2 Accounts**: SectionHeader(Accounts)+See all → 2×AccountTile → SectionHeader(Recent
  Transaction) → TxRow card → BottomNav.
- **S3 Wallet**: app-identity header → StackCard rows (Adobe, Spotify highlighted) →
  FeatureCard (Netflix, $14.95, Pending −$3.00) → Digital Card mask row.
- **S4 Target**: PageHeader → ProgressCard summary (92 % left, mini bar) → ProgressCard
  (savings this month, slider) → BannerPill (saved $1200, 🔥×3) → SectionHeader(Your Stats) →
  2×2 StatsCard → BottomNav.

## 5. Mapping onto Artha

| Mock motif                 | Artha screen & data                                                     |
|----------------------------|-------------------------------------------------------------------------|
| S1 hero + ChartCard        | Dashboard: hero greeting, Net worth ChartCard with pill badge           |
| S1 StatTiles               | Dashboard: Income / Spending this month from `dashboardProvider.flows`  |
| S1 ActivityCards           | Dashboard: "Needs attention" insight card + upcoming recurring bills    |
| S4 ProgressCard+BannerPill | Dashboard: savings-this-month progress card + saved banner (flows)      |
| S4 StatsCard grid          | Dashboard KPI grid (net worth, cash, debt, savings rate, emergency fund)|
| S2 AccountTiles            | Accounts page groups as tile grids                                      |
| S2 TxRow                   | Accounts recent list, Transactions page rows, account ledger rows       |
| S3 FeatureCard             | Account detail balance hero                                             |
| S4 stats/progress styling  | Insights & Reports cards inherit via theme                              |
| Theme manager (new)        | Settings → Appearance: palette cards + System/Light/Dark mode           |

## 6. Theme manager spec

- Palettes ship in `lib/ui/theme.dart`: **Indigo Paper** (default, the mock), **Indigo Night**
  is its dark rendering, plus **Emerald** (Artha's legacy brand), **Ocean**, **Rose**. Each
  palette defines both brightness renderings of the token roles in §2.1.
- Choice persists per device in local settings: `ui.theme` (palette id) and `ui.mode`
  (`system` | `light` | `dark`), same store as `fx.auto`; never synced.
- Settings → Appearance card: mode SegmentedButton (System/Light/Dark) and a wrap of palette
  cards (name + four swatch dots + selected check). Changes apply live, no restart.
- `MaterialApp.theme` / `darkTheme` / `themeMode` come from `appearanceProvider`; core widgets
  (AppShell, PageScaffold, SectionCard, dialogs) restyle automatically because they read
  `Theme.of(context)`.
- Chart series colours travel in a `ThemeExtension` so charts follow the palette; categorical
  asset-class colours stay with core `ChartColors`.

## 7. Fidelity guardrails

- Hints (`Hint`, page banners) stay on every control; the redesign changes skin, not semantics.
- Status and income colours always pair with an icon (core rule); never colour alone.
- Money stays tabular (`tabular` from core) in every tile, row and axis.
- Empty, loading and error states keep core widgets; they inherit the new skin.
