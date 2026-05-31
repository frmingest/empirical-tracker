interface StatusBadgeProps {
  inRange: boolean | null;
  showLabel?: boolean;
  size?: "sm" | "md";
}

export function StatusBadge({
  inRange,
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
