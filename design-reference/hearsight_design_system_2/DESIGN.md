---
name: HearSight Design System
colors:
  surface: '#131313'
  surface-dim: '#131313'
  surface-bright: '#393939'
  surface-container-lowest: '#0e0e0e'
  surface-container-low: '#1c1b1b'
  surface-container: '#201f1f'
  surface-container-high: '#2a2a2a'
  surface-container-highest: '#353534'
  on-surface: '#e5e2e1'
  on-surface-variant: '#bbc9cf'
  inverse-surface: '#e5e2e1'
  inverse-on-surface: '#313030'
  outline: '#859399'
  outline-variant: '#3c494e'
  surface-tint: '#4cd6ff'
  primary: '#a4e6ff'
  on-primary: '#003543'
  primary-container: '#00d1ff'
  on-primary-container: '#00566a'
  inverse-primary: '#00677f'
  secondary: '#dab9ff'
  on-secondary: '#460283'
  secondary-container: '#602b9d'
  on-secondary-container: '#cfa7ff'
  tertiary: '#dfdcdb'
  on-tertiary: '#313030'
  tertiary-container: '#c3c0bf'
  on-tertiary-container: '#4f4e4e'
  error: '#ffb4ab'
  on-error: '#690005'
  error-container: '#93000a'
  on-error-container: '#ffdad6'
  primary-fixed: '#b7eaff'
  primary-fixed-dim: '#4cd6ff'
  on-primary-fixed: '#001f28'
  on-primary-fixed-variant: '#004e60'
  secondary-fixed: '#eedbff'
  secondary-fixed-dim: '#dab9ff'
  on-secondary-fixed: '#2a0053'
  on-secondary-fixed-variant: '#5e289b'
  tertiary-fixed: '#e5e2e1'
  tertiary-fixed-dim: '#c9c6c5'
  on-tertiary-fixed: '#1c1b1b'
  on-tertiary-fixed-variant: '#474646'
  background: '#131313'
  on-background: '#e5e2e1'
  surface-variant: '#353534'
typography:
  display-xl:
    fontFamily: Space Grotesk
    fontSize: 48px
    fontWeight: '700'
    lineHeight: '1.1'
    letterSpacing: 0.02em
  display-lg:
    fontFamily: Space Grotesk
    fontSize: 36px
    fontWeight: '600'
    lineHeight: '1.2'
    letterSpacing: 0.02em
  headline-md:
    fontFamily: Space Grotesk
    fontSize: 24px
    fontWeight: '500'
    lineHeight: '1.3'
    letterSpacing: 0.01em
  body-lg:
    fontFamily: Atkinson Hyperlegible Next
    fontSize: 20px
    fontWeight: '400'
    lineHeight: '1.6'
    letterSpacing: 0.01em
  body-md:
    fontFamily: Atkinson Hyperlegible Next
    fontSize: 18px
    fontWeight: '400'
    lineHeight: '1.5'
    letterSpacing: 0.01em
  label-caps:
    fontFamily: Space Grotesk
    fontSize: 14px
    fontWeight: '600'
    lineHeight: '1.0'
    letterSpacing: 0.15em
rounded:
  sm: 0.5rem
  DEFAULT: 1rem
  md: 1.5rem
  lg: 2rem
  xl: 3rem
  full: 9999px
spacing:
  unit: 8px
  margin-mobile: 24px
  margin-desktop: 64px
  gutter: 16px
  container-padding: 32px
---

## Brand & Style
The design system is a premium, cinematic visual language engineered for AI-augmented navigation and accessibility. It prioritizes emotional reassurance and safety through a high-tech, futuristic lens. The aesthetic is "Dark Mode First," drawing inspiration from high-end automotive interfaces and minimalist sci-fi HUDs.

The style leverages **Glassmorphism** and **Atmospheric Lighting** to create a sense of depth and spatial awareness. By using deep blacks and charcoal tones as the foundation, the system allows high-contrast accents to guide the user’s eye. The interface feels less like a traditional app and more like a sophisticated environmental overlay, emphasizing a "calm technology" philosophy where the UI recedes until needed.

## Colors
The palette is rooted in the void—using **Deep Black (#050505)** for base surfaces to maximize OLED efficiency and visual comfort. **Charcoal (#121212)** serves as the primary container color, providing a subtle lift from the background.

**Electric Blue (#00D1FF)** is the "Navigation Prime" color, used for active paths, pulse effects, and primary actions. **Neon Purple (#BB86FC)** acts as the "Intelligence" accent, signifying AI processing, voice states, and secondary highlights. Gradients should transition from Electric Blue to a deep translucent sapphire to simulate glowing gas or light refraction.

## Typography
Legibility is the cornerstone of this design system. It utilizes **Space Grotesk** for headlines and interactive labels to provide a technical, futuristic edge. For all body and descriptive text, **Atkinson Hyperlegible Next** is mandated to ensure maximum clarity for users with visual impairments.

Key typographic rules:
- **Generous Letter Spacing:** Enhanced tracking on all labels to prevent "character crowding."
- **High Contrast:** All text must meet a minimum 7:1 contrast ratio against background layers.
- **Scale:** Sizes are intentionally oversized to facilitate quick scanning while moving or in low-light environments.

## Layout & Spacing
The layout follows a **Fluid Grid** approach with an emphasis on "Safe Areas." Because the app is used for navigation, content is pushed toward the center-bottom and side-rails to allow the camera view (or radar) to remain the primary focus.

- **Floating Layers:** UI elements do not touch the screen edges; they float with a 24px minimum margin.
- **Spatial Rhythm:** A strict 8px base unit is used, but internal padding for cards and containers is typically larger (32px+) to create a luxurious, premium sense of space.
- **Visual Hierarchy:** Critical navigation data (distance, direction) occupies the largest typographic real estate in the lower third of the screen.

## Elevation & Depth
Depth is communicated through **Backdrop Blurs** and **Luminous Borders** rather than traditional shadows. 

1. **Surface 0 (Base):** Pure Black (#050505).
2. **Surface 1 (Floating):** Charcoal (#121212) with a 20px background blur and a 1px internal stroke of white at 8% opacity.
3. **Surface 2 (Active/Focus):** The same as Surface 1 but with a subtle outer "Atmospheric Glow" using the Primary Electric Blue at very low opacity (10-15%).

Interaction triggers "Pulse" effects—concentric rings that emanate from the point of touch or the identified object, reinforcing the radar-inspired metaphor.

## Shapes
The geometry of the design system is organic and soft, contrasting with the technical nature of the AI. Surfaces use **Super-ellipses (Squircles)** and ultra-rounded corners (24px to 32px) to feel friendly and safe. 

Buttons and high-level navigation items are always **Pill-shaped**. This eliminates sharp "visual noise" and focuses the user’s attention on the content within the container. Radar elements and pulse indicators use perfect circles to maintain a consistent spatial language.

## Components

### Buttons & Interaction
- **Primary Action:** Pill-shaped, Electric Blue background with high-contrast black text. Includes a subtle "inner glow" on the top edge.
- **Ghost Action:** Transparent background with a 1px Electric Blue border and text.

### Navigation Cards
Cards use high-level Glassmorphism. They must feature a "Light Leak" effect—a subtle gradient originating from the top-left corner—to simulate an external light source hitting the glass surface.

### Radar/Spatial HUD
The core component of the design system. It consists of concentric, translucent rings centered on the user's location. Objects detected by the AI appear as "Glow Orbs" that pulse in synchronization with haptic feedback.

### Feedback Systems
- **The Pulse:** A circular ripple animation used for searching states and confirming object detection.
- **The Beam:** A linear gradient pathing system in Electric Blue that "leads" the user's eye toward their destination.

### Input Fields
Minimalist charcoal wells with "floating labels" that transition into Electric Blue when focused. The caret is a 2px thick block to ensure visibility.