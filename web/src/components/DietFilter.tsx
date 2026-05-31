"use client";

import { DIET_OPTIONS, type DietKey } from "@/lib/dietProfiles";
import { useLanguage } from "./LanguageProvider";

interface Props {
  diet: DietKey;
  onSelect: (diet: DietKey) => void;
  onCustomize: () => void;
  visibleCount: number;
  totalCount: number;
}

/**
 * Segmented control that picks the diet focus. Presets/All apply immediately;
 * "Custom" and the "Customize" link open the marker picker.
 */
export function DietFilter({
  diet,
  onSelect,
  onCustomize,
  visibleCount,
  totalCount,
}: Props) {
  const { t } = useLanguage();
  const active = DIET_OPTIONS.find((o) => o.key === diet);

  return (
    <div className="rounded-xl border border-[var(--border-card)] bg-[var(--bg-card)] px-3 py-3 shadow-sm">
      <div className="flex items-center justify-between gap-3 flex-wrap">
        <div className="flex items-center gap-2 flex-wrap">
          <span className="text-[10px] uppercase tracking-widest text-[var(--text-muted)] mr-1 select-none">
            {t("diet.focus")}
          </span>
          <div
            role="group"
            aria-label={t("diet.focus")}
            className="flex items-center gap-1 flex-wrap"
          >
            {DIET_OPTIONS.map((opt) => {
              const isActive = diet === opt.key;
              return (
                <button
                  key={opt.key}
                  onClick={() => onSelect(opt.key)}
                  aria-pressed={isActive}
                  title={t(`diet.${opt.key}.desc`)}
                  className={`text-xs font-medium px-3 py-1.5 rounded-lg border transition-colors ${
                    isActive
                      ? "bg-[var(--color-accent)] text-white border-transparent"
                      : "border-[var(--border-card)] text-[var(--text-secondary)] hover:text-[var(--text-primary)] hover:bg-[var(--bg-elevated)]"
                  }`}
                >
                  {t(`diet.${opt.key}.label`)}
                </button>
              );
            })}
          </div>
        </div>

        <div className="flex items-center gap-3">
          <span className="text-xs text-[var(--text-muted)] font-mono tabular-nums">
            {diet === "all"
              ? `${totalCount} ${t("diet.markers")}`
              : `${visibleCount} / ${totalCount}`}
          </span>
          {diet !== "all" && (
            <button
              onClick={onCustomize}
              className="text-xs font-medium text-[var(--color-accent)] hover:underline"
            >
              {diet === "custom" ? t("diet.edit") : t("diet.customize")}
            </button>
          )}
        </div>
      </div>

      {active && diet !== "all" && (
        <p className="mt-2 text-xs text-[var(--text-secondary)] leading-relaxed">
          {t(`diet.${diet}.desc`)}
        </p>
      )}
    </div>
  );
}
