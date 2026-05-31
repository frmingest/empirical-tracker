import Link from "next/link";
import { notFound } from "next/navigation";
import { BiomarkerChart } from "@/components/BiomarkerChart";
import { StatusBadge } from "@/components/StatusBadge";
import { MOCK_RESULTS } from "@/lib/mockData";
import {
  fmtDateLong,
  getCategory,
  shortLabel,
} from "@/lib/biomarkerCategories";

interface Props {
  params: Promise<{ id: string }>;
}

export default async function BiomarkerDetailPage({ params }: Props) {
  const { id } = await params;

  // TODO: replace with getBiomarkerResults(token) when auth is wired
  const entry = MOCK_RESULTS.find((r) => r.biomarker.id === id);
  if (!entry) notFound();

  const { biomarker, series } = entry;
  const latest = series.at(-1);
  const category = getCategory(biomarker.name_no);

  return (
    <div className="min-h-screen bg-[#09090b]">
      {/* Nav */}
      <header className="sticky top-0 z-40 border-b border-zinc-900 bg-[#09090b]/90 backdrop-blur-md">
        <div className="max-w-3xl mx-auto px-4 sm:px-6 h-14 flex items-center gap-3">
          <Link
            href="/"
            className="text-zinc-500 hover:text-zinc-300 transition-colors text-sm"
          >
            ← Dashboard
          </Link>
          <span className="text-zinc-800">·</span>
          <span className="text-xs text-zinc-600 uppercase tracking-wide">
            {category}
          </span>
        </div>
      </header>

      <main className="max-w-3xl mx-auto px-4 sm:px-6 py-8 space-y-6">
        {/* Biomarker header */}
        <div className="space-y-2">
          <div className="flex items-start justify-between gap-4">
            <h1 className="text-xl font-semibold text-zinc-100 leading-tight">
              {shortLabel(biomarker.name_no)}
            </h1>
            {latest && <StatusBadge inRange={latest.in_range} showLabel size="md" />}
          </div>
          {biomarker.name_no !== shortLabel(biomarker.name_no) && (
            <p className="text-xs text-zinc-600 font-mono">{biomarker.name_no}</p>
          )}
        </div>

        {/* Current value + ref range */}
        <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
          <div className="rounded-xl border border-zinc-800 bg-zinc-900 px-4 py-4">
            <p className="text-[10px] uppercase tracking-widest text-zinc-600 mb-1.5">
              Latest value
            </p>
            <p className="text-2xl font-mono font-semibold text-zinc-100 tabular-nums">
              {latest?.value ?? "—"}
            </p>
            {biomarker.unit && (
              <p className="text-xs text-zinc-600 font-mono mt-0.5">{biomarker.unit}</p>
            )}
          </div>

          {latest && (
            <div className="rounded-xl border border-zinc-800 bg-zinc-900 px-4 py-4">
              <p className="text-[10px] uppercase tracking-widest text-zinc-600 mb-1.5">
                Test date
              </p>
              <p className="text-sm text-zinc-300 leading-snug">
                {fmtDateLong(latest.tested_at)}
              </p>
            </div>
          )}

          <div className="rounded-xl border border-zinc-800 bg-zinc-900 px-4 py-4">
            <p className="text-[10px] uppercase tracking-widest text-zinc-600 mb-1.5">
              Reference
            </p>
            <p className="text-sm font-mono text-zinc-400">
              {biomarker.ref_range_raw || "—"}
            </p>
          </div>

          <div className="rounded-xl border border-zinc-800 bg-zinc-900 px-4 py-4">
            <p className="text-[10px] uppercase tracking-widest text-zinc-600 mb-1.5">
              Data points
            </p>
            <p className="text-2xl font-mono font-semibold text-zinc-100">
              {series.length}
            </p>
          </div>
        </div>

        {/* Trend chart */}
        <div>
          <h2 className="text-xs uppercase tracking-widest text-zinc-600 mb-3">
            Trend over time
          </h2>
          <BiomarkerChart data={entry} />
        </div>

        {/* History table */}
        {series.length > 0 && (
          <div>
            <h2 className="text-xs uppercase tracking-widest text-zinc-600 mb-3">
              All results
            </h2>
            <div className="rounded-xl border border-zinc-800 bg-zinc-900 overflow-hidden">
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b border-zinc-800">
                    <th className="text-left px-4 py-3 text-[10px] uppercase tracking-widest text-zinc-600 font-normal">
                      Date
                    </th>
                    <th className="text-right px-4 py-3 text-[10px] uppercase tracking-widest text-zinc-600 font-normal">
                      Value
                    </th>
                    <th className="text-right px-4 py-3 text-[10px] uppercase tracking-widest text-zinc-600 font-normal">
                      Status
                    </th>
                  </tr>
                </thead>
                <tbody>
                  {[...series].reverse().map((point, i) => (
                    <tr
                      key={point.tested_at}
                      className={i < series.length - 1 ? "border-b border-zinc-800/60" : ""}
                    >
                      <td className="px-4 py-3 text-zinc-400 text-xs">
                        {fmtDateLong(point.tested_at)}
                      </td>
                      <td className="px-4 py-3 text-right font-mono text-zinc-100 tabular-nums">
                        {point.value}
                        {biomarker.unit && (
                          <span className="text-zinc-600 ml-1 text-xs">{biomarker.unit}</span>
                        )}
                      </td>
                      <td className="px-4 py-3 text-right">
                        <StatusBadge inRange={point.in_range} showLabel size="sm" />
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        )}
      </main>
    </div>
  );
}
