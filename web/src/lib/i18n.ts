import type { Category } from "./biomarkerCategories";

/** Supported UI languages. English is the default/fallback. */
export type Lang = "en" | "no";

export const LANGS: Lang[] = ["en", "no"];

/** Short label shown on the language toggle for each language. */
export const LANG_LABELS: Record<Lang, string> = {
  en: "EN",
  no: "NO",
};

type Dict = Record<string, string>;

// ── UI strings ────────────────────────────────────────────────────────────────
const en: Dict = {
  // nav
  "nav.panels": "Panels",
  "nav.foodDiary": "Food diary",
  "nav.mealPlans": "Meal plans",
  "nav.addResult": "Add result",
  "nav.import": "Import",
  "nav.signOut": "Sign out",
  "nav.signIn": "Sign in",
  // mock-data banner
  "banner.mock": "Showing mock data.",
  "banner.signInPrompt": "to see your real results.",
  // hero
  "hero.title": "Blood biomarkers",
  "hero.yourData": "Your data",
  "hero.sampleData": "Sample data",
  "hero.subtitle": "personal health tracking for elimination diets",
  // stats
  "stats.biomarkers": "Biomarkers",
  "stats.panels": "Test panels",
  "stats.lastTested": "Last tested",
  "stats.outOfRange": "Out of range",
  // empty state
  "empty.none": "No markers selected for this view.",
  "empty.choose": "Choose markers",
  // footer
  "footer.live": "Live data from Supabase",
  "footer.mock": "Mock data — sign in to load your results",
  // category section
  "category.off": "off",
  "category.aboutGroup": "About this group",
  // diet filter
  "diet.focus": "Diet focus",
  "diet.markers": "markers",
  "diet.edit": "Edit selection",
  "diet.customize": "Customize",
  "diet.all.label": "All",
  "diet.all.desc": "Show every biomarker in your panel.",
  "diet.carnivore.label": "Carnivore",
  "diet.carnivore.desc":
    "Lipid response, iron stores, kidney load, liver enzymes, electrolytes and B-vitamin / folate status — the markers most affected by an all-meat diet.",
  "diet.low_carb.label": "Low carb",
  "diet.low_carb.desc":
    "Glycemic control (HbA1c), the full lipid panel, liver enzymes and the electrolytes that shift when you cut carbs.",
  "diet.fasting.label": "Fasting",
  "diet.fasting.desc":
    "Electrolytes, glucose control, kidney and liver markers, plus hydration-sensitive blood counts to watch during a fast.",
  "diet.custom.label": "Custom",
  "diet.custom.desc": "Hand-pick exactly which biomarkers you want to follow.",
  // language toggle
  "lang.toggle": "Switch language",
};

const no: Dict = {
  // nav
  "nav.panels": "Paneler",
  "nav.foodDiary": "Matdagbok",
  "nav.mealPlans": "Måltidsplaner",
  "nav.addResult": "Legg til resultat",
  "nav.import": "Importer",
  "nav.signOut": "Logg ut",
  "nav.signIn": "Logg inn",
  // mock-data banner
  "banner.mock": "Viser eksempeldata.",
  "banner.signInPrompt": "for å se dine egne resultater.",
  // hero
  "hero.title": "Blodbiomarkører",
  "hero.yourData": "Dine data",
  "hero.sampleData": "Eksempeldata",
  "hero.subtitle": "personlig helseoppfølging for eliminasjonsdietter",
  // stats
  "stats.biomarkers": "Biomarkører",
  "stats.panels": "Testpaneler",
  "stats.lastTested": "Sist testet",
  "stats.outOfRange": "Utenfor referanse",
  // empty state
  "empty.none": "Ingen markører er valgt for denne visningen.",
  "empty.choose": "Velg markører",
  // footer
  "footer.live": "Sanntidsdata fra Supabase",
  "footer.mock": "Eksempeldata — logg inn for å laste dine resultater",
  // category section
  "category.off": "utenfor",
  "category.aboutGroup": "Om denne gruppen",
  // diet filter
  "diet.focus": "Diettfokus",
  "diet.markers": "markører",
  "diet.edit": "Rediger utvalg",
  "diet.customize": "Tilpass",
  "diet.all.label": "Alle",
  "diet.all.desc": "Vis alle biomarkører i panelet ditt.",
  "diet.carnivore.label": "Karnivor",
  "diet.carnivore.desc":
    "Lipidrespons, jernlagre, nyrebelastning, leverenzymer, elektrolytter og B-vitamin-/folatstatus — markørene som påvirkes mest av et rent kjøttkosthold.",
  "diet.low_carb.label": "Lavkarbo",
  "diet.low_carb.desc":
    "Blodsukkerkontroll (HbA1c), hele lipidpanelet, leverenzymer og elektrolyttene som endrer seg når du kutter karbohydrater.",
  "diet.fasting.label": "Faste",
  "diet.fasting.desc":
    "Elektrolytter, blodsukkerkontroll, nyre- og levermarkører, samt væskefølsomme blodverdier å følge med på under en faste.",
  "diet.custom.label": "Egendefinert",
  "diet.custom.desc": "Velg nøyaktig hvilke biomarkører du vil følge.",
  // language toggle
  "lang.toggle": "Bytt språk",
};

export const translations: Record<Lang, Dict> = { en, no };

/** Look up a UI string, falling back to English, then to the raw key. */
export function translate(lang: Lang, key: string): string {
  return translations[lang][key] ?? translations.en[key] ?? key;
}

// ── Biomarker grouping labels ───────────────────────────────────────────────────
/** Display name for each biomarker grouping, per language. */
export const CATEGORY_LABELS: Record<Lang, Record<Category, string>> = {
  en: {
    Lipids: "Lipids",
    CBC: "CBC",
    Metabolic: "Metabolic",
    Thyroid: "Thyroid",
    Renal: "Renal",
    Liver: "Liver",
    Nutrients: "Nutrients",
    Electrolytes: "Electrolytes",
    Other: "Other",
  },
  no: {
    Lipids: "Lipider",
    CBC: "Blodstatus",
    Metabolic: "Metabolsk",
    Thyroid: "Stoffskifte",
    Renal: "Nyrer",
    Liver: "Lever",
    Nutrients: "Næringsstoffer",
    Electrolytes: "Elektrolytter",
    Other: "Annet",
  },
};

// ── Plain-language explanations of each grouping (tooltip content) ──────────────
/**
 * Plain-language descriptions of what each biomarker grouping measures and why
 * it matters. Written for a non-clinical reader — these power the info tooltips
 * next to each grouping heading.
 */
export const CATEGORY_DESCRIPTIONS: Record<Lang, Record<Category, string>> = {
  en: {
    Lipids:
      "Fats in your blood such as cholesterol and triglycerides. They affect your heart and blood vessels — out-of-range levels can raise the risk of clogged arteries.",
    CBC: "Complete Blood Count — your red and white blood cells and platelets. Shows how well your blood carries oxygen, fights infection, and clots.",
    Metabolic:
      "Blood-sugar markers like glucose and HbA1c. They show how your body handles sugar over time and are used to screen for diabetes.",
    Thyroid:
      "Hormones from your thyroid gland (like TSH and T4). They control your metabolism, energy levels, and body temperature.",
    Renal:
      "Kidney markers like creatinine and GFR. They show how well your kidneys are filtering waste out of your blood.",
    Liver:
      "Liver enzymes and proteins (like ALAT and ASAT). They reveal how hard your liver is working and whether it is stressed or damaged.",
    Nutrients:
      "Vitamins and minerals such as iron, B12, folate, and vitamin D. They show whether your body has enough of the building blocks it needs.",
    Electrolytes:
      "Charged minerals like sodium, potassium, and calcium. They keep your nerves, muscles, and fluid balance working properly.",
    Other:
      "Markers that don't fall into the main groups. Open each one to see what it measures.",
  },
  no: {
    Lipids:
      "Fettstoffer i blodet, som kolesterol og triglyserider. De påvirker hjertet og blodårene dine — verdier utenfor referansen kan øke risikoen for tette blodårer.",
    CBC: "Komplett blodtelling — røde og hvite blodlegemer og blodplater. Viser hvor godt blodet transporterer oksygen, bekjemper infeksjon og levrer seg.",
    Metabolic:
      "Blodsukkermarkører som glukose og HbA1c. De viser hvordan kroppen håndterer sukker over tid, og brukes til å oppdage diabetes.",
    Thyroid:
      "Hormoner fra skjoldbruskkjertelen (som TSH og T4). De styrer stoffskiftet, energinivået og kroppstemperaturen din.",
    Renal:
      "Nyremarkører som kreatinin og GFR. De viser hvor godt nyrene dine filtrerer avfallsstoffer ut av blodet.",
    Liver:
      "Leverenzymer og proteiner (som ALAT og ASAT). De viser hvor hardt leveren din jobber, og om den er belastet eller skadet.",
    Nutrients:
      "Vitaminer og mineraler som jern, B12, folat og vitamin D. De viser om kroppen har nok av byggesteinene den trenger.",
    Electrolytes:
      "Ladede mineraler som natrium, kalium og kalsium. De holder nerver, muskler og væskebalanse i orden.",
    Other:
      "Markører som ikke hører hjemme i hovedgruppene. Åpne hver enkelt for å se hva den måler.",
  },
};
