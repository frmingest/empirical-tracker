"use client";
import { createContext, useContext, useEffect, useState } from "react";
import { translate, type Lang } from "@/lib/i18n";

interface LanguageContextValue {
  lang: Lang;
  setLang: (lang: Lang) => void;
  toggleLang: () => void;
  /** Translate a UI string key for the active language. */
  t: (key: string) => string;
}

const LanguageContext = createContext<LanguageContextValue>({
  lang: "en",
  setLang: () => {},
  toggleLang: () => {},
  t: (key) => key,
});

/** html lang attribute: Norwegian Bokmål for "no", otherwise English. */
const htmlLang = (lang: Lang) => (lang === "no" ? "nb" : "en");

export function LanguageProvider({ children }: { children: React.ReactNode }) {
  const [lang, setLangState] = useState<Lang>("en");

  useEffect(() => {
    const saved = (localStorage.getItem("lang") as Lang) ?? "en";
    // eslint-disable-next-line react-hooks/set-state-in-effect
    setLangState(saved);
    document.documentElement.lang = htmlLang(saved);
  }, []);

  const setLang = (next: Lang) => {
    setLangState(next);
    localStorage.setItem("lang", next);
    document.documentElement.lang = htmlLang(next);
  };

  const toggleLang = () => setLang(lang === "en" ? "no" : "en");

  const t = (key: string) => translate(lang, key);

  return (
    <LanguageContext.Provider value={{ lang, setLang, toggleLang, t }}>
      {children}
    </LanguageContext.Provider>
  );
}

export const useLanguage = () => useContext(LanguageContext);
