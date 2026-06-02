"use client";

import Link from "next/link";
import { categorySlug, type Category } from "@/lib/biomarkerCategories";
import { CATEGORY_LABELS } from "@/lib/i18n";
import { useLanguage } from "./LanguageProvider";

export interface CategoryNavItem {
  category: Category;
  /** Number of biomarkers in this group for the current diet view. */
  count: number;
  /** How many of those are out of range — surfaced as a small badge. */
  outOfRange: number;
}

interface Props {
  /** Groups with at least one marker, in display order. */
  items: CategoryNavItem[];
  active: Category;
}

/**
 * Horizontal, scrollable rail of category chips. Lets the user hop straight
 * from one group's graph view to another without bouncing back to the
 * dashboard. The active group is highlighted; each chip is a plain link so
 * navigation works without JS and preserves browser history.
 */
export function CategoryNav({ items, active }: Props) {
  const { lang, t } = useLanguage();

  return (
    <nav
      aria-label={t("category.jumpTo")}
      className="flex items-center gap-2 overflow-x-auto pb-1 -mx-1 px-1"
    >
      {items.map(({ category, count, outOfRange }) => {
        const isActive = category === active;
        return (
          <Link
            key={category}
            href={`/categories/${categorySlug(category)}`}
            aria-current={isActive ? "page" : undefined}
            scroll={false}
            className={`shrink-0 flex items-center gap-1.5 rounded-full px-3.5 py-1.5 text-sm font-medium transition-colors focus:outline-none focus-visible:ring-2 focus-visible:ring-[var(--color-accent)] ${
              isActive
                ? "bg-[var(--color-accent)] text-[var(--btn-accent-text)]"
                : "border border-[var(--border-card)] bg-[var(--bg-card)] text-[var(--text-secondary)] hover:text-[var(--text-primary)] hover:bg-[var(--bg-elevated)]"
            }`}
          >
            <span>{CATEGORY_LABELS[lang][category]}</span>
            <span
              className={`font-mono text-xs tabular-nums ${
                isActive ? "opacity-80" : "text-[var(--text-muted)]"
              }`}
            >
              {count}
            </span>
            {outOfRange > 0 && (
              <span
                className={`h-1.5 w-1.5 rounded-full ${
                  isActive ? "bg-[var(--btn-accent-text)]" : "bg-rose-500"
                }`}
                aria-hidden
              />
            )}
          </Link>
        );
      })}
    </nav>
  );
}
