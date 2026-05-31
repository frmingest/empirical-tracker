import type { BiomarkerWithSeries } from "@/lib/api";
import type { Category } from "@/lib/biomarkerCategories";
import { BiomarkerCard } from "./BiomarkerCard";

const CATEGORY_ICONS: Record<Category, string> = {
  Lipids:       "◈",
  CBC:          "◉",
  Metabolic:    "◎",
  Thyroid:      "◐",
  Renal:        "◑",
  Liver:        "◒",
  Nutrients:    "◓",
  Electrolytes: "◔",
  Other:        "○",
};

interface Props {
  category: Category;
  items: BiomarkerWithSeries[];
}

export function CategorySection({ category, items }: Props) {
  if (items.length === 0) return null;

  const outOfRangeCount = items.filter((i) => {
    const latest = i.series.at(-1);
    return latest?.in_range === false;
  }).length;

  return (
    <section>
      <div className="flex items-center gap-3 mb-4">
        <span className="text-[var(--text-muted)] text-sm select-none">
          {CATEGORY_ICONS[category]}
        </span>
        <h2 className="text-xs font-semibold uppercase tracking-widest text-[var(--text-secondary)]">
          {category}
        </h2>
        <div className="flex-1 h-px bg-[var(--border-subtle)]" />
        <span className="text-xs text-[var(--text-muted)] font-mono">
          {items.length}
        </span>
        {outOfRangeCount > 0 && (
          <span className="text-xs font-mono text-rose-500 bg-rose-500/10 px-1.5 py-0.5 rounded">
            {outOfRangeCount} off
          </span>
        )}
      </div>

      <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5 gap-3">
        {items.map((item) => (
          <BiomarkerCard key={item.biomarker.id} data={item} />
        ))}
      </div>
    </section>
  );
}
