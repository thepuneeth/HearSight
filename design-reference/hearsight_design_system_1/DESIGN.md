---
name: HearSight Design System
colors:
  surface: '#141218'
  surface-dim: '#141218'
  surface-bright: '#3b383e'
  surface-container-lowest: '#0f0d13'
  surface-container-low: '#1d1b20'
  surface-container: '#211f24'
  surface-container-high: '#2b292f'
  surface-container-highest: '#36343a'
  on-surface: '#e6e0e9'
  on-surface-variant: '#cbc4d2'
  inverse-surface: '#e6e0e9'
  inverse-on-surface: '#322f35'
  outline: '#948e9c'
  outline-variant: '#494551'
  surface-tint: '#cfbcff'
  primary: '#cfbcff'
  on-primary: '#381e72'
  primary-container: '#6750a4'
  on-primary-container: '#e0d2ff'
  inverse-primary: '#6750a4'
  secondary: '#cdc0e9'
  on-secondary: '#342b4b'
  secondary-container: '#4d4465'
  on-secondary-container: '#bfb2da'
  tertiary: '#e7c365'
  on-tertiary: '#3e2e00'
  tertiary-container: '#c9a74d'
  on-tertiary-container: '#503d00'
  error: '#ffb4ab'
  on-error: '#690005'
  error-container: '#93000a'
  on-error-container: '#ffdad6'
  primary-fixed: '#e9ddff'
  primary-fixed-dim: '#cfbcff'
  on-primary-fixed: '#22005d'
  on-primary-fixed-variant: '#4f378a'
  secondary-fixed: '#e9ddff'
  secondary-fixed-dim: '#cdc0e9'
  on-secondary-fixed: '#1f1635'
  on-secondary-fixed-variant: '#4b4263'
  tertiary-fixed: '#ffdf93'
  tertiary-fixed-dim: '#e7c365'
  on-tertiary-fixed: '#241a00'
  on-tertiary-fixed-variant: '#594400'
  background: '#141218'
  on-background: '#e6e0e9'
  surface-variant: '#36343a'
typography:
  display-xl:
    fontFamily: Space Grotesk
    fontSize: 48px
    fontWeight: '700'
    lineHeight: 56px
    letterSpacing: -0.02em
  headline-lg:
    fontFamily: Space Grotesk
    fontSize: 32px
    fontWeight: '600'
    lineHeight: 40px
  headline-lg-mobile:
    fontFamily: Space Grotesk
    fontSize: 28px
    fontWeight: '600'
    lineHeight: 36px
  body-xl:
    fontFamily: Space Grotesk
    fontSize: 24px
    fontWeight: '500'
    lineHeight: 32px
  body-md:
    fontFamily: Space Grotesk
    fontSize: 18px
    fontWeight: '400'
    lineHeight: 28px
  label-lg:
    fontFamily: Space Grotesk
    fontSize: 16px
    fontWeight: '600'
    lineHeight: 24px
    letterSpacing: 0.05em
rounded:
  sm: 0.25rem
  DEFAULT: 0.5rem
  md: 0.75rem
  lg: 1rem
  xl: 1.5rem
  full: 9999px
spacing:
  touch-target-min: 64px
  gutter: 24px
  margin-mobile: 20px
  margin-desktop: 48px
  stack-gap: 32px
---

## Brand & Style

This design system is engineered for **HearSight**, a platform where high-stakes utility meets cinematic immersion. The brand personality is "Empowering Futurity"—combining the precision of an advanced AI navigator with the warmth of a human assistant. It aims to evoke a sense of confidence, clarity, and supernatural perception for visually impaired users.

The aesthetic follows a **Cinematic HUD / Glassmorphic** direction for the primary dark mode, utilizing light as the primary navigational tool rather than structural containers. The secondary light mode shifts toward a **Tactile / Organic** style, focusing on soft, physical metaphors and calming, high-readability surfaces. Across both modes, the design system prioritizes "Minimal Chrome," where depth, atmosphere, and light gradients define boundaries, reducing cognitive load and focusing the user on one singular, decisive action at a time.

## Colors

The color strategy is divided into two distinct emotional states:

**Primary (Dark Mode):** Designed for high-contrast spatial awareness. Pure black (#000000) maximizes OLED contrast, while deep charcoal (#0e0e0e) provides subtle depth for secondary surfaces. Electric Cyan (#00d1ff) acts as the primary "Active" or "Focus" state, symbolizing AI intelligence. Neon Violet (#8b5cf6) is reserved for spatial cues, peripheral information, and secondary actions.

**Secondary (Warm Light Mode):** Designed for low-stress, long-form interaction. It utilizes soft parchment (#fdfcfb) to reduce eye strain. Accents of Rich Amber (#f59e0b) and Terra Cotta (#e27d60) provide a tactile, human-centric feel that mimics the qualities of physical paper and clay.

In both modes, color is used sparingly to direct attention. Gradients are utilized to indicate "directionality" of sound or objects in the user's environment.

## Typography

Typography in this design system is oversized and high-contrast to ensure maximum legibility. **Space Grotesk** is used across all levels for its technical yet accessible geometric character. 

Hierarchy is established through extreme scale differences. The "Display" and "Headline" levels are intended for primary status updates (e.g., "Doorway detected"), while "Body-XL" is the default for most interactive text. Every character must remain distinct; avoid tight kerning. In the Dark theme, use pure white text on black backgrounds. In the Light theme, use deep charcoal text on parchment backgrounds to maintain a minimum 7:1 contrast ratio.

## Layout & Spacing

This design system uses a **Contextual No-Grid** philosophy centered on safe areas and massive touch targets. The primary rule is "One Screen, One Action." Elements are positioned relative to the thumb-zone for mobile users and centered for desktop/tablet HUD views.

- **Touch Targets:** A mandatory minimum of 64px for all interactive elements to accommodate motor-skill variances and non-visual interaction.
- **Rhythm:** A vertical stack rhythm of 32px (stack-gap) ensures clear separation between distinct pieces of information.
- **Safe Zones:** Generous margins (20px on mobile) ensure that UI elements do not bleed into the edges of the hardware, which is critical for users who navigate by feeling the edge of the device.
- **Atmospheric Spacing:** Use padding to create "pools of light" around content, rather than using lines to separate items.

## Elevation & Depth

Depth is used to convey information importance and spatial distance.

- **Primary Dark Mode:** Uses **Glassmorphism**. Layers are defined by backdrop blurs (20px to 40px) and varying levels of transparency (10% to 30%). Ambient glows in Electric Cyan or Neon Violet are placed *behind* active elements to create a "halo" effect, signaling that an element is interactive or has the current system focus.
- **Secondary Light Mode:** Uses **Tonal Layering**. Depth is achieved through subtle color shifts (e.g., a Parchment White surface floating on a Warm Cream background). Shadows are ultra-diffused, soft-amber-tinted "contact shadows" that make elements feel like physical objects resting on a surface.
- **Transitioning:** Movement between layers should feel fluid. When a new UI element appears, it should fade in while "scaling up" slightly, mimicking an object moving closer to the user.

## Shapes

The design system utilizes **Rounded (Level 2)** geometry. This strikes a balance between the technical precision of the AI platform and the approachability required for an assistive tool.

- **Base Radius:** 0.5rem (8px) for standard cards and buttons.
- **Large Components:** 1rem (16px) for main content layers and modal-like sheets.
- **Interactive States:** Active targets may expand their radius slightly when focused to provide a "softer" tactile feel in the visual language.
- **Icons:** Must use a minimum 2px stroke weight with rounded caps and joins to match the outer container geometry.

## Components

Components in this design system are designed to be "felt" visually.

- **Buttons:** Primary buttons are 64px high, spanning the full width of the safe area. In Dark mode, they are semi-transparent glass with a vibrant glow; in Light mode, they are solid terra cotta or amber with a slight inner-press shadow.
- **Chips/Status Tags:** Small, pill-shaped indicators with high-contrast backgrounds. Used for metadata like "Distance: 2m" or "Object: Person."
- **Lists:** Items have a minimum height of 80px. Instead of dividers, use vertical spacing or very subtle tonal shifts between items.
- **Input Fields:** Oversized borders (2px) appear only on focus. The default state is a simple dark/light surface with high-contrast placeholder text.
- **Cards:** Floating layers with no hard borders. In the HUD aesthetic, cards are defined by their background blur and a thin "light leak" gradient on the top edge to simulate a physical light source.
- **Haptic Indicators:** While not visual, all components must trigger a distinct haptic pulse when the user's finger enters the 64px touch zone, synchronized with a visual "glow" expansion.