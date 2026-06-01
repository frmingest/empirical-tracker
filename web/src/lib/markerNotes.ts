import { markerKey, type MarkerKey } from "./dietProfiles";
import type { Lang } from "./i18n";

/**
 * Per-marker interpretation notes — "confounder tooltips" (Sprint 8).
 *
 * A handful of markers are routinely *misread* on a carnivore / low-carb /
 * fasting protocol because the diet itself moves the number for reasons that
 * have nothing to do with the thing the marker is usually taken to mean. These
 * notes name that confounder in plain language so the user reads the value with
 * the right caveat.
 *
 * Like the diet-focus lists (`dietProfiles.ts`) and clinical targets
 * (`clinicalTargets.ts`), these are **universal, marker-level facts, not
 * per-user data** — so they live as a static map keyed by `markerKey()`, with
 * no database table and no migration. They are **decision-support, not medical
 * advice**, and never claim what an individual's value means.
 */

export interface MarkerNote {
  /** Short heading, per language. */
  title: Record<Lang, string>;
  /** Plain-language confounder explanation, per language. */
  body: Record<Lang, string>;
}

const NOTES: Partial<Record<MarkerKey, MarkerNote>> = {
  egfr: {
    title: {
      en: "Why this can read low on a meat-heavy diet",
      no: "Hvorfor denne kan se lav ut på et kjøttrikt kosthold",
    },
    body: {
      en: "This eGFR is estimated from creatinine, which rises with a high meat intake and with more muscle mass — so a fit, high-protein eater can show a lower eGFR without any real drop in kidney function. A cystatin-C–based eGFR is less affected by diet and muscle and is the better check if this looks low.",
      no: "Denne eGFR-en er beregnet fra kreatinin, som stiger ved høyt kjøttinntak og med mer muskelmasse — så en veltrent person med høyt proteininntak kan vise lavere eGFR uten at nyrefunksjonen faktisk er redusert. En cystatin-C-basert eGFR påvirkes mindre av kosthold og muskler, og er den bedre kontrollen hvis denne ser lav ut.",
    },
  },
  hba1c: {
    title: {
      en: "Why this can read high on keto / carnivore",
      no: "Hvorfor denne kan se høy ut på keto / karnivor",
    },
    body: {
      en: "HbA1c reflects how long your red blood cells live, not just your average blood sugar. On a low-carb or carnivore diet red cells often live longer, so they accumulate more glucose over their lifespan and HbA1c can read paradoxically high even when day-to-day glucose is excellent. A fasting glucose or a continuous glucose monitor gives a less confounded picture.",
      no: "HbA1c gjenspeiler hvor lenge de røde blodlegemene dine lever, ikke bare gjennomsnittlig blodsukker. På et lavkarbo- eller karnivorkosthold lever røde blodlegemer ofte lenger, så de samler opp mer glukose i løpet av levetiden, og HbA1c kan se paradoksalt høy ut selv når blodsukkeret fra dag til dag er utmerket. Fastende glukose eller kontinuerlig glukosemåling gir et mindre forstyrret bilde.",
    },
  },
  ferritin: {
    title: {
      en: "Ferritin is not only an iron store",
      no: "Ferritin er ikke bare et jernlager",
    },
    body: {
      en: "Ferritin is also an acute-phase reactant: it rises with inflammation, infection, liver stress, and recent alcohol — not only when iron stores are high. A raised ferritin on a high-heme-iron carnivore diet can mean iron loading, inflammation, or both. Pairing it with transferrin / transferrin saturation and an inflammation marker separates the two.",
      no: "Ferritin er også et akuttfasereaktant: det stiger ved betennelse, infeksjon, leverbelastning og nylig alkohol — ikke bare når jernlagrene er høye. Et forhøyet ferritin på et karnivorkosthold rikt på hem-jern kan bety jernopphopning, betennelse eller begge deler. Å se det sammen med transferrin / transferrinmetning og en betennelsesmarkør skiller de to.",
    },
  },
};

/** Interpretation note for a marker by its raw Norwegian name, or null. */
export function markerNote(nameNo: string): MarkerNote | null {
  const key = markerKey(nameNo);
  return key ? NOTES[key] ?? null : null;
}
