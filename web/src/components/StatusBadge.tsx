interface StatusBadgeProps {
  inRange: boolean | null;
  /**
   * Sprint 7 — when true and the value is *not* out of range, the badge shows an
   * amber "Watch" state: the value is within the lab reference but a clinical
   * target or trend signal is flagged. An out-of-range value always wins.
   */
  attention?: boolean;
  showLabel?: boolean;
  size?: "sm" | "md";
}

type Kind = "ok" | "watch" | "alert" | "unknown";

/**
 * Status is conveyed by **shape as well as colour**, so it survives red/green
 * colour-blindness (≈8% of men) and greyscale printing:
 *   ok → circle · watch → triangle · alert → diamond · unknown → dash.
 * The wrapper carries a `role="img"` + `aria-label` so screen readers announce
 * the status even when no text label is shown.
 */
function StatusGlyph({ kind, px }: { kind: Kind; px: number }) {
  const color =
    kind === "alert"
      ? "var(--color-out-range)"
      : kind === "watch"
        ? "var(--color-warning)"
        : kind === "ok"
          ? "var(--color-in-range)"
          : "var(--text-muted)";

  const shape =
    kind === "ok" ? (
      <circle cx="5" cy="5" r="4" />
    ) : kind === "watch" ? (
      <path d="M5 0.6 L9.4 9 L0.6 9 Z" />
    ) : kind === "alert" ? (
      <path d="M5 0.6 L9.4 5 L5 9.4 L0.6 5 Z" />
    ) : (
      <rect x="0.8" y="4.1" width="8.4" height="1.8" rx="0.9" />
    );

  return (
    <svg
      width={px}
      height={px}
      viewBox="0 0 10 10"
      fill={color}
      aria-hidden="true"
      className="shrink-0"
    >
      {shape}
    </svg>
  );
}

export function StatusBadge({
  inRange,
  attention = false,
  showLabel = false,
  size = "md",
}: StatusBadgeProps) {
  const kind: Kind =
    inRange === null
      ? "unknown"
      : inRange === false
        ? "alert"
        : attention
          ? "watch"
          : "ok";

  const label =
    kind === "unknown"
      ? "No data"
      : kind === "alert"
        ? "Out of range"
        : kind === "watch"
          ? "Watch"
          : "In range";

  const textColor =
    kind === "alert"
      ? "var(--color-out-range)"
      : kind === "watch"
        ? "var(--color-warning)"
        : kind === "ok"
          ? "var(--color-in-range)"
          : "var(--text-muted)";

  const px = size === "sm" ? 9 : 11;

  return (
    <span
      className="inline-flex items-center gap-1.5"
      role="img"
      aria-label={label}
    >
      <StatusGlyph kind={kind} px={px} />
      {showLabel && (
        <span className="text-xs font-mono" style={{ color: textColor }}>
          {kind === "unknown" ? "—" : label}
        </span>
      )}
    </span>
  );
}
