---
name: Warm Light Mode
colors:
  surface: '#fbf9f8'
  surface-dim: '#dcd9d9'
  surface-bright: '#fbf9f8'
  surface-container-lowest: '#ffffff'
  surface-container-low: '#f6f3f2'
  surface-container: '#f0eded'
  surface-container-high: '#eae8e7'
  surface-container-highest: '#e4e2e1'
  on-surface: '#1b1c1c'
  on-surface-variant: '#564334'
  inverse-surface: '#303030'
  inverse-on-surface: '#f3f0f0'
  outline: '#897362'
  outline-variant: '#ddc1ae'
  surface-tint: '#904d00'
  primary: '#904d00'
  on-primary: '#ffffff'
  primary-container: '#ff8c00'
  on-primary-container: '#623200'
  inverse-primary: '#ffb77d'
  secondary: '#685e3e'
  on-secondary: '#ffffff'
  secondary-container: '#f0e2ba'
  on-secondary-container: '#6e6444'
  tertiary: '#795900'
  on-tertiary: '#ffffff'
  tertiary-container: '#d6a21a'
  on-tertiary-container: '#523b00'
  error: '#ba1a1a'
  on-error: '#ffffff'
  error-container: '#ffdad6'
  on-error-container: '#93000a'
  primary-fixed: '#ffdcc3'
  primary-fixed-dim: '#ffb77d'
  on-primary-fixed: '#2f1500'
  on-primary-fixed-variant: '#6e3900'
  secondary-fixed: '#f0e2ba'
  secondary-fixed-dim: '#d4c69f'
  on-secondary-fixed: '#221b03'
  on-secondary-fixed-variant: '#4f4629'
  tertiary-fixed: '#ffdfa0'
  tertiary-fixed-dim: '#f6be39'
  on-tertiary-fixed: '#261a00'
  on-tertiary-fixed-variant: '#5c4300'
  background: '#fbf9f8'
  on-background: '#1b1c1c'
  surface-variant: '#e4e2e1'
typography:
  display-lg:
    fontFamily: Space Grotesk
    fontSize: 48px
    fontWeight: '700'
    lineHeight: '1.1'
    letterSpacing: -0.02em
  headline-lg:
    fontFamily: Space Grotesk
    fontSize: 32px
    fontWeight: '700'
    lineHeight: '1.2'
  headline-lg-mobile:
    fontFamily: Space Grotesk
    fontSize: 28px
    fontWeight: '700'
    lineHeight: '1.2'
  body-xl:
    fontFamily: Space Grotesk
    fontSize: 24px
    fontWeight: '500'
    lineHeight: '1.5'
  body-lg:
    fontFamily: Space Grotesk
    fontSize: 20px
    fontWeight: '500'
    lineHeight: '1.5'
  label-xl:
    fontFamily: Space Grotesk
    fontSize: 18px
    fontWeight: '700'
    lineHeight: '1.2'
rounded:
  sm: 0.25rem
  DEFAULT: 0.5rem
  md: 0.75rem
  lg: 1rem
  xl: 1.5rem
  full: 9999px
spacing:
  unit: 8px
  margin-mobile: 24px
  margin-desktop: 64px
  gutter: 16px
  touch-target-min: 64px
---

## Brand & Style

The design system is a human-centric accessibility framework that prioritizes cognitive ease and visual comfort during daylight hours. The brand personality is one of a "trusted companion"—reassuring, safe, and premium. It avoids the clinical coldness of traditional accessibility tools, opting instead for a "Warm Light" aesthetic that feels organic and inviting.

The visual style is a blend of **Soft Minimalism** and **Refined Glassmorphism**. It utilizes atmospheric lighting and gentle depth rather than structural lines to define space. By removing harsh black borders and high-frequency visual noise, the system reduces cognitive load for users who may be visually impaired or navigating high-glare environments. The experience is audio-first, where the interface serves as a tactile, supportive surface for voice-driven interactions.

## Colors

This design system utilizes a high-contrast yet "soft-edge" palette to ensure legibility without causing eye strain. 

- **Backgrounds:** The foundation is #FDFCFB (Parchment), providing a soft, non-reflective base that performs better than pure white in bright sunlight.
- **Accents:** #FF8C00 (Amber) is used for primary actions and state changes, providing a warm, high-visibility signal. 
- **Gradients:** "Golden-Honey" linear gradients (Amber to Deep Gold) are used sparingly to indicate active audio streams or tactile depth.
- **Text:** Charcoal-grey (#333333) is used for all primary text to maintain a high contrast ratio (7:1+) against the cream background while appearing more natural than absolute black.

## Typography

Typography in this design system is oversized and structurally bold to facilitate rapid scanning. **Space Grotesk** is used across all levels; its geometric clarity and distinctive character shapes aid users with low vision or dyslexia.

- **Weight as Hierarchy:** We rely on heavy weights (Bold/700) for headlines and Medium (500) for body text to ensure characters never appear "thin" or "ghosted" against the warm background.
- **Oversized Scale:** The minimum body text size starts at 20px. 
- **Readability:** Line heights are generous (1.5 for body) to prevent crowding, and slight negative letter spacing is applied to display sizes to keep the geometric forms cohesive.

## Layout & Spacing

The layout philosophy follows a **Fluid Grid** model with extreme "safe zones." Because the product is designed for "eyes-busy" or "vision-impaired" scenarios, the spacing rhythm is intentionally loose.

- **Massive Touch Targets:** A minimum touch target of 64px is enforced for all interactive elements to accommodate motor-skill variations and sunlight-induced glare.
- **Minimal Clutter:** Layouts should never exceed 3 primary interactive zones per screen.
- **Adaptation:** On mobile, components stack vertically with 24px side margins. On tablet and desktop, the system utilizes a centered 8-column grid to keep content within the primary field of view, preventing the need for excessive eye scanning.

## Elevation & Depth

This design system rejects harsh shadows and lines in favor of **Atmospheric Depth**. 

- **Tonal Layering:** Depth is primarily communicated through subtle shifts in saturation. Lower surfaces use the base Parchment color, while elevated cards use a slightly brighter, filtered "Soft Light" effect.
- **Glassmorphism:** Overlays and modals use a high-refraction backdrop blur (20px+) with a semi-transparent #FDFCFB fill. This maintains the "Warm Light" feel while clearly separating the interaction layer from the background.
- **Shadows:** Use "Amber-Tinted" shadows—extremely diffused, low-opacity (8-12%) glows that mimic the way light wraps around a physical object in a sunlit room. Avoid grey or black shadows.

## Shapes

The shape language is consistently **Rounded**, evoking a sense of safety and approachability. 

- **Soft Corners:** The standard corner radius is 0.5rem (8px), which scales up to 1.5rem (24px) for large containers and cards.
- **Organic Feel:** By avoiding sharp 90-degree angles, the system feels less like a "technical interface" and more like a physical object.
- **Continuous Curves:** Buttons and chips should feel "squishy" and tactile, inviting touch without the aggression of sharp corners.

## Components

- **Buttons:** Primary buttons are large (64px height) with a Golden-Honey gradient background and Charcoal text. They feature a subtle inner-glow to suggest a convex, tactile surface.
- **Cards:** Use a 24px radius and a "Soft Light" elevation. Cards should not have borders; instead, they are defined by a 1px "Light Leak" (a lighter cream stroke on the top and left edges).
- **Lists:** List items are separated by generous 16px gaps rather than divider lines. Each item acts as a large, rounded container to maximize hit area.
- **Input Fields:** Fields use a slightly darker parchment tint (#F5E1CE) with 700-weight Charcoal text. The focus state is a 4px Amber outer-glow.
- **Audio Visualizers:** A bespoke "Pulse" component using the Amber accent color should be used to provide visual feedback for audio-first interactions, appearing as a soft, expanding ring.
- **Haptic Feedback:** While visual, all components are designed with the assumption of accompanying haptic and audio triggers.