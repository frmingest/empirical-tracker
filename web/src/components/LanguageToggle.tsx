"use client";
import { useLanguage } from "./LanguageProvider";
import { LANG_LABELS } from "@/lib/i18n";

export function LanguageToggle() {
  const { lang, toggleLang, t } = useLanguage();
  return (
    <button
      onClick={toggleLang}
      aria-label={t("lang.toggle")}
      title={t("lang.toggle")}
      className="h-8 px-2 min-w-8 flex items-center justify-center gap-1 rounded-lg border border-[var(--border-card)] bg-[var(--bg-elevated)] text-[var(--text-secondary)] hover:text-[var(--text-primary)] hover:bg-[var(--bg-card)] transition-colors"
    >
      <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
        <circle cx="12" cy="12" r="10" /><line x1="2" y1="12" x2="22" y2="12" /><path d="M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1-4-10 15.3 15.3 0 0 1 4-10z" />
      </svg>
      <span className="text-[11px] font-semibold tabular-nums">{LANG_LABELS[lang]}</span>
    </button>
  );
}
