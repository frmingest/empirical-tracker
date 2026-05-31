async function getApiHealth() {
  const base = process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:8000";
  try {
    const res = await fetch(`${base}/health`, { cache: "no-store" });
    if (!res.ok) return { status: "unreachable" as const };
    return (await res.json()) as { status: string; environment?: string };
  } catch {
    return { status: "unreachable" as const };
  }
}

export default async function Home() {
  const health = await getApiHealth();
  const ok = health.status === "ok";

  return (
    <main className="flex min-h-screen flex-col items-center justify-center gap-6 p-8">
      <h1 className="text-3xl font-bold">Empirical Tracker</h1>
      <p className="text-gray-500">Health tracker for elimination diets.</p>
      <div className="rounded-lg border px-4 py-3 text-sm">
        API status:{" "}
        <span className={ok ? "text-green-600" : "text-red-600"}>
          {ok ? "connected" : "unreachable"}
        </span>
        {health.environment ? ` (${health.environment})` : null}
      </div>
    </main>
  );
}
