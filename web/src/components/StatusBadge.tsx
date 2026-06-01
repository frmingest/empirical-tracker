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

export function StatusBadge({
  inRange,
  attention = false,
  showLabel = false,
  size = "md",
}: StatusBadgeProps) {
  const dotSize = size === "sm" ? "w-1.5 h-1.5" : "w-2 h-2";

  if (inRange === null) {
    return (
      <span className="inline-flex items-center gap-1.5">
        <span className={`${dotSize} rounded-full bg-[var(--text-muted)]`} />
        {showLabel && (
          <span className="text-xs text-[var(--text-muted)] font-mono">—</span>
        )}
      </span>
    );
  }

  // In range, but a target/trend signal wants attention → amber "Watch".
  if (inRange && attention) {
    return (
      <span className="inline-flex items-center gap-1.5">
        <span
          className={`${dotSize} rounded-full bg-amber-500 shadow-[0_0_6px_rgba(217,160,68,0.6)]`}
        />
        {showLabel && (
          <span className="text-xs font-mono text-[var(--color-warning)]">
            Watch
          </span>
        )}
      </span>
    );
  }

  return (
    <span className="inline-flex items-center gap-1.5">
      <span
        className={`${dotSize} rounded-full ${
          inRange
            ? "bg-emerald-400 shadow-[0_0_6px_rgba(52,211,153,0.6)]"
            : "bg-rose-400 shadow-[0_0_6px_rgba(248,113,113,0.6)]"
        }`}
      />
      {showLabel && (
        <span
          className={`text-xs font-mono ${
            inRange ? "text-emerald-400" : "text-rose-400"
          }`}
        >
          {inRange ? "In range" : "Out of range"}
        </span>
      )}
    </span>
  );
}
