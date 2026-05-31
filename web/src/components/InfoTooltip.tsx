"use client";
import { useEffect, useId, useRef, useState } from "react";

interface Props {
  /** Accessible label for the trigger button (e.g. "About this group"). */
  label: string;
  /** Plain-language explanation shown in the popover. */
  text: string;
}

/**
 * Small "ⓘ" button that reveals a plain-language explanation. Opens on hover and
 * on focus/click (so it works with touch and keyboard too), closes on Escape,
 * blur, or an outside click. No external tooltip library — styled with the app's
 * CSS custom properties.
 */
export function InfoTooltip({ label, text }: Props) {
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLSpanElement>(null);
  const tipId = useId();

  useEffect(() => {
    if (!open) return;
    const onPointer = (e: MouseEvent | TouchEvent) => {
      if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false);
    };
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") setOpen(false);
    };
    document.addEventListener("mousedown", onPointer);
    document.addEventListener("touchstart", onPointer);
    document.addEventListener("keydown", onKey);
    return () => {
      document.removeEventListener("mousedown", onPointer);
      document.removeEventListener("touchstart", onPointer);
      document.removeEventListener("keydown", onKey);
    };
  }, [open]);

  return (
    <span
      ref={ref}
      className="relative inline-flex"
      onMouseEnter={() => setOpen(true)}
      onMouseLeave={() => setOpen(false)}
    >
      <button
        type="button"
        aria-label={label}
        aria-expanded={open}
        aria-describedby={open ? tipId : undefined}
        onClick={() => setOpen((o) => !o)}
        onFocus={() => setOpen(true)}
        onBlur={() => setOpen(false)}
        className="w-4 h-4 flex items-center justify-center rounded-full border border-[var(--border-card)] text-[10px] font-semibold leading-none text-[var(--text-muted)] hover:text-[var(--text-primary)] hover:border-[var(--text-secondary)] focus:outline-none focus-visible:ring-2 focus-visible:ring-[var(--color-accent)] transition-colors"
      >
        i
      </button>
      {open && (
        <span
          id={tipId}
          role="tooltip"
          className="absolute left-0 top-6 z-50 block w-64 rounded-lg border border-[var(--border-card)] bg-[var(--bg-surface)] px-3 py-2 text-xs font-normal normal-case leading-relaxed tracking-normal text-[var(--text-secondary)] shadow-lg"
        >
          {text}
        </span>
      )}
    </span>
  );
}
