/** @type {import('tailwindcss').Config} */
export default {
  content: ["./index.html", "./src/**/*.{js,ts,jsx,tsx}"],
  theme: {
    extend: {
      colors: {
        // Design tokens FOJEM — repris de niou_dem/lib/core/theme/app_colors.dart
        // (échantillonnage pixel des maquettes officielles). Ne jamais coder
        // une couleur en dur dans un composant : toujours passer par ces
        // tokens Tailwind.
        primary: {
          DEFAULT: "#EA671A",
          light: "#F08C4C",
          surface: "#FFF2DB",
        },
        danger: {
          DEFAULT: "#BE4947",
          surface: "#F7E8E7",
        },
        success: {
          DEFAULT: "#32963C",
          surface: "#ECF5EB",
        },
        bg: "#FBF9F7",
        surface: "#FFFFFF",
        ink: {
          primary: "#0B2A47",
          secondary: "#5B5B58",
          muted: "#A0A09A",
        },
        line: {
          DEFAULT: "#E8E6E0",
          strong: "#C8C6C0",
        },
        // Deuxième teinte de série (graphiques à 2 séries uniquement) —
        // validée par le validateur de palette du skill dataviz (ΔE normal
        // 30.8, ΔE protan 21.4 vs primary). Jamais réutilisée pour un statut.
        chart: {
          secondary: "#3D6FA8",
        },
      },
      fontFamily: {
        sans: ["Inter", "ui-sans-serif", "system-ui", "sans-serif"],
      },
      borderRadius: {
        sm: "6px",
        md: "12px",
        lg: "20px",
      },
      boxShadow: {
        card: "0 2px 8px rgba(11,42,71,0.06), 0 0 1px rgba(11,42,71,0.04)",
      },
    },
  },
  plugins: [],
};
