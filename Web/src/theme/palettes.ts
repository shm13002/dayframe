// Mirror of App/Dayflow/Utilities/DayflowTheme.swift (light/dark base) and
// DayframePalette.swift (the six palettes). Keep the two in sync: if a value
// changes in Swift, change it here too.

export type PaletteName = "original" | "lagoon" | "lavender" | "matcha" | "rose" | "ember";
export type Mode = "light" | "dark";

export const PALETTES: readonly PaletteName[] = [
  "original",
  "lagoon",
  "lavender",
  "matcha",
  "rose",
  "ember",
];

/** Everything a palette changes. Values are CSS colors. */
export interface PaletteTokens {
  windowBackground: string;
  accent: string;
  accentText: string;
  controlFill: string;
  controlBorder: string;
  controlGlow: string;
  buttonFill: string;
  buttonBorder: string;
  buttonGlow: string;
  softFill: string;
  softBorder: string;
}

/** Everything that depends only on light/dark. */
export interface BaseTokens {
  textPrimary: string;
  textSecondary: string;
  textTertiary: string;
  textMuted: string;
  controlText: string;
  buttonText: string;
  cardFill: string;
  cardBorder: string;
  cardTitle: string;
  cardTime: string;
  shellGradient: string;
  shellBorder: string;
  shellHeading: string;
  shellShadow: string;
  shellGlow: string;
  inputFill: string;
  inputBorder: string;
  statFill: string;
  statBorder: string;
  popoverFill: string;
  popoverBorder: string;
  danger: string;
}

const hex = (h: string, alpha = 1): string => {
  const n = Number.parseInt(h, 16);
  const r = (n >> 16) & 255;
  const g = (n >> 8) & 255;
  const b = n & 255;
  return alpha === 1 ? `#${h}` : `rgba(${r}, ${g}, ${b}, ${alpha})`;
};

const lightBackground = (stops: [string, string, string], center = "64% 100%", at = [17, 33, 100]) =>
  `radial-gradient(1250px circle at ${center}, ${hex(stops[0])} ${at[0]}%, ${hex(stops[1])} ${at[1]}%, ${hex(stops[2])} ${at[2]}%)`;

const darkBackground = (stops: [string, string, string]) =>
  `linear-gradient(75deg, ${hex(stops[0])} 21%, ${hex(stops[1])} 53%, ${hex(stops[2])} 105%)`;

export const BASE: Record<Mode, BaseTokens> = {
  light: {
    textPrimary: "#333333",
    textSecondary: "#707070",
    textTertiary: "#787878",
    textMuted: "#979797",
    controlText: "#606060",
    buttonText: "#FFFFFF",
    cardFill: "rgba(255, 255, 255, 0.9)",
    cardBorder: "#D0D0D0",
    cardTitle: "#333333",
    cardTime: "#979797",
    shellGradient:
      "linear-gradient(90deg, rgba(255,255,255,0.2) 0%, rgba(255,255,255,0.7) 50%, rgba(255,255,255,0.2) 100%)",
    shellBorder: "#DADADA",
    shellHeading: "#90837A",
    shellShadow: "0 4px 16px rgba(0, 0, 0, 0.1)",
    shellGlow: "inset 0 0 6px #FFFFFF",
    inputFill: "rgba(255, 255, 255, 0.9)",
    inputBorder: "#E1E1E1",
    statFill: "rgba(255, 255, 255, 0.75)",
    statBorder: "#F2EEEC",
    popoverFill: "rgba(250, 245, 242, 0.97)",
    popoverBorder: "#E8E0DE",
    danger: "#E5484D",
  },
  dark: {
    textPrimary: "#FFFFFF",
    textSecondary: "#DDDDDD",
    textTertiary: "#B3B3B3",
    textMuted: "#B4B4B4",
    controlText: "#FFFFFF",
    buttonText: "#FFFFFF",
    cardFill: "rgba(255, 255, 255, 0.15)",
    cardBorder: "#999999",
    cardTitle: "#FFFFFF",
    cardTime: "#B4B4B4",
    shellGradient:
      "linear-gradient(90deg, rgba(128,123,147,0.152) 0%, rgba(222,218,239,0.152) 50%, rgba(128,123,147,0.152) 100%)",
    shellBorder: "#4E4E4E",
    shellHeading: "#DDDDDD",
    shellShadow: "0 4px 16px rgba(0, 0, 0, 0.12)",
    shellGlow: "none",
    inputFill: "rgba(255, 255, 255, 0.1)",
    inputBorder: "#666666",
    statFill: "rgba(255, 255, 255, 0.12)",
    statBorder: "#717171",
    popoverFill: "rgba(39, 41, 58, 0.97)",
    popoverBorder: "#585858",
    danger: "#FF6B6B",
  },
};

interface Spec {
  lightBG: [string, string, string];
  darkBG: [string, string, string];
  accent: string;
  accentTextLight: string;
  accentTextDark: string;
  controlFill: string;
  controlBorder: string;
  controlGlow: string;
  buttonLight: string;
  buttonDark: string;
  softFill: string;
}

const SPECS: Record<Exclude<PaletteName, "original">, Spec> = {
  lagoon: {
    lightBG: ["C9F2EA", "DDEFFF", "E4E2FF"], darkBG: ["1E4A57", "233548", "2C2F55"],
    accent: "1C9E94", accentTextLight: "45BDB2", accentTextDark: "6ED8CC",
    controlFill: "B6EAE2", controlBorder: "C6E2DD", controlGlow: "E3F8F4",
    buttonLight: "2BB3A7", buttonDark: "1C8C83", softFill: "E8F8F5",
  },
  lavender: {
    lightBG: ["E6D9FF", "FFE1EE", "D9E6FF"], darkBG: ["3B2F66", "33304F", "4A2A55"],
    accent: "8A63F2", accentTextLight: "A98BFF", accentTextDark: "C2A9FF",
    controlFill: "DCCBFF", controlBorder: "DCD2EE", controlGlow: "F1EAFF",
    buttonLight: "9874F5", buttonDark: "6F4FD1", softFill: "F3EEFF",
  },
  matcha: {
    lightBG: ["DDEFC8", "F4EED6", "D6ECE2"], darkBG: ["2D4A33", "2E3B35", "3D3A2C"],
    accent: "5C9A3B", accentTextLight: "7DB85A", accentTextDark: "A2D67F",
    controlFill: "D2E9BD", controlBorder: "D8E3CB", controlGlow: "EEF7E4",
    buttonLight: "6DAA49", buttonDark: "4F8A33", softFill: "F1F8E9",
  },
  rose: {
    lightBG: ["FFD6DD", "FFE8D8", "EEDDF7"], darkBG: ["5A2D40", "432F45", "4D3242"],
    accent: "E0557A", accentTextLight: "F27C9B", accentTextDark: "FF9DB7",
    controlFill: "FFC9D3", controlBorder: "F0D3D9", controlGlow: "FFEAEE",
    buttonLight: "EC6B8D", buttonDark: "C24767", softFill: "FFF0F3",
  },
  ember: {
    lightBG: ["FFD0A8", "FFC7B8", "E3D2F5"], darkBG: ["5C3420", "4A2B3E", "35285A"],
    accent: "F06A1F", accentTextLight: "FF8F4F", accentTextDark: "FFA36B",
    controlFill: "FFC39C", controlBorder: "EFCDB8", controlGlow: "FFE6D6",
    buttonLight: "F57A33", buttonDark: "C9551A", softFill: "FFF0E5",
  },
};

/** Dayflow's own peach-and-sky theme (DayflowTheme.swift, light and dark blocks). */
const ORIGINAL: Record<Mode, PaletteTokens> = {
  light: {
    windowBackground: lightBackground(["FFE6CF", "FFE6E0", "DAEAFC"], "59% 100%", [0, 37, 99]),
    accent: "#F3854B",
    accentText: "#FFA376",
    controlFill: "#FFD2B9",
    controlBorder: "#EAD5CD",
    controlGlow: "#FFECE6",
    buttonFill: "#FF9F6F",
    buttonBorder: "#F4C8B1",
    buttonGlow: "rgba(255, 220, 203, 0.9)",
    softFill: "#FFF4E9",
    softBorder: hex("F96E00", 0.25),
  },
  dark: {
    windowBackground: darkBackground(["303C5B", "313348", "3B294B"]),
    accent: "#F3854B",
    accentText: "#F77952",
    controlFill: "rgba(226, 160, 121, 0.4)",
    controlBorder: "#875C46",
    controlGlow: "rgba(243, 182, 152, 0.5)",
    buttonFill: "#D1653E",
    buttonBorder: "#EA9265",
    buttonGlow: "rgba(255, 135, 77, 0.9)",
    softFill: hex("F3854B", 0.18),
    softBorder: hex("F77952", 0.4),
  },
};

/** Same rules as DayframePalette.apply(to:). */
export function paletteTokens(name: PaletteName, mode: Mode): PaletteTokens {
  if (name === "original") return ORIGINAL[mode];
  const s = SPECS[name];
  if (mode === "dark") {
    return {
      windowBackground: darkBackground(s.darkBG),
      accent: hex(s.accent),
      accentText: hex(s.accentTextDark),
      controlFill: hex(s.accent, 0.4),
      controlBorder: hex(s.accent, 0.7),
      controlGlow: hex(s.accentTextDark, 0.5),
      buttonFill: hex(s.buttonDark),
      buttonBorder: hex(s.accentTextDark),
      buttonGlow: hex(s.accentTextDark, 0.9),
      softFill: hex(s.accent, 0.18),
      softBorder: hex(s.accentTextDark, 0.4),
    };
  }
  return {
    windowBackground: lightBackground(s.lightBG),
    accent: hex(s.accent),
    accentText: hex(s.accentTextLight),
    controlFill: hex(s.controlFill),
    controlBorder: hex(s.controlBorder),
    controlGlow: hex(s.controlGlow),
    buttonFill: hex(s.buttonLight),
    buttonBorder: hex(s.controlBorder),
    buttonGlow: hex(s.controlGlow, 0.9),
    softFill: hex(s.softFill),
    softBorder: hex(s.accent, 0.25),
  };
}

/** Raw background stops and accents, for surfaces that draw their own light (the welcome show). */
export interface PaletteStops {
  dark: [string, string, string];
  light: [string, string, string];
  accent: string;
  accentLight: string;
  accentDark: string;
}

export function paletteStops(name: PaletteName): PaletteStops {
  if (name === "original") {
    return {
      dark: ["303C5B", "313348", "3B294B"],
      light: ["FFE6CF", "FFE6E0", "DAEAFC"],
      accent: "F3854B",
      accentLight: "FFA376",
      accentDark: "F77952",
    };
  }
  const s = SPECS[name];
  return { dark: s.darkBG, light: s.lightBG, accent: s.accent, accentLight: s.accentTextLight, accentDark: s.accentTextDark };
}

export function isPaletteName(value: string | null | undefined): value is PaletteName {
  return value != null && (PALETTES as readonly string[]).includes(value);
}

const kebab = (key: string) => key.replace(/[A-Z]/g, (c) => `-${c.toLowerCase()}`);

/** Writes the tokens as --df-* custom properties on <html>. */
export function applyTheme(name: PaletteName, mode: Mode, root: HTMLElement = document.documentElement): void {
  const tokens: Record<string, string> = { ...BASE[mode], ...paletteTokens(name, mode) };
  for (const [key, value] of Object.entries(tokens)) {
    root.style.setProperty(`--df-${kebab(key)}`, value);
  }
  root.dataset.palette = name;
  root.dataset.theme = mode;
  root.style.colorScheme = mode;
}
