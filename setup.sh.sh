#!/usr/bin/env bash
# Run: bash setup.sh   (creates the ClipGenius project in ./clipgenius)
set -e
mkdir -p clipgenius && cd clipgenius
mkdir -p "."
cat > "./.env.example" <<'CLIPGENIUS_EOF'
# Public (safe for the browser)
NEXT_PUBLIC_SUPABASE_URL=
NEXT_PUBLIC_SUPABASE_ANON_KEY=
NEXT_PUBLIC_SITE_URL=http://localhost:3000

# Server only (never prefix with NEXT_PUBLIC_). Used from Phase 2 onward.
SUPABASE_SERVICE_ROLE_KEY=

CLIPGENIUS_EOF
mkdir -p "."
cat > "./.gitignore" <<'CLIPGENIUS_EOF'
node_modules
.next
.env
.env.local
next-env.d.ts

CLIPGENIUS_EOF
mkdir -p "."
cat > "./README.md" <<'CLIPGENIUS_EOF'
# ClipGenius AI: Phase 1 (foundation)

## Set up
1. Create a Supabase project (supabase.com).
2. In the SQL editor, run `supabase/migrations/0001_schema.sql`.
3. Auth > Providers: email is on by default. For Google login, add a Google OAuth client and paste its ID/secret.
4. Auth > URL Configuration: Site URL `http://localhost:3000`, add redirect `http://localhost:3000/auth/callback`.
5. `cp .env.example .env.local` and fill in the project URL and anon key (Settings > API).
6. `npm install && npm run typecheck && npm run dev`

## Test checklist
- /signup creates a user; a row appears in `profiles` (plan_id = free).
- Visiting /dashboard logged out redirects to /login.
- Dashboard shows zeros and the Free plan meters; Projects and Plan & usage pages load.
- Insert a test project in the SQL editor for your user id; it appears on Dashboard and Projects.
- Log out works. Two different users cannot see each other's rows (RLS).

CLIPGENIUS_EOF
mkdir -p "."
cat > "./next.config.mjs" <<'CLIPGENIUS_EOF'
/** @type {import('next').NextConfig} */
const nextConfig = { reactStrictMode: true };
export default nextConfig;

CLIPGENIUS_EOF
mkdir -p "."
cat > "./package.json" <<'CLIPGENIUS_EOF'
{
  "name": "clipgenius-web",
  "version": "0.1.0",
  "private": true,
  "scripts": { "dev": "next dev", "build": "next build", "start": "next start", "lint": "next lint", "typecheck": "tsc --noEmit" },
  "dependencies": {
    "@supabase/ssr": "^0.5.2",
    "@supabase/supabase-js": "^2.45.4",
    "lucide-react": "^0.454.0",
    "next": "^15.0.3",
    "react": "^19.0.0",
    "react-dom": "^19.0.0"
  },
  "devDependencies": {
    "@types/node": "^22.9.0",
    "@types/react": "^19.0.0",
    "@types/react-dom": "^19.0.0",
    "autoprefixer": "^10.4.20",
    "postcss": "^8.4.49",
    "tailwindcss": "^3.4.15",
    "typescript": "^5.6.3"
  }
}

CLIPGENIUS_EOF
mkdir -p "."
cat > "./postcss.config.mjs" <<'CLIPGENIUS_EOF'
export default { plugins: { tailwindcss: {}, autoprefixer: {} } };

CLIPGENIUS_EOF
mkdir -p "./src/app/(app)/billing"
cat > "./src/app/(app)/billing/page.tsx" <<'CLIPGENIUS_EOF'
import { createClient } from "@/lib/supabase/server";
import { formatBytes } from "@/lib/format";

export const dynamic = "force-dynamic";

export default async function BillingPage() {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  const [{ data: plans }, { data: profile }] = await Promise.all([
    supabase.from("plans").select("*").order("sort_order"),
    supabase.from("profiles").select("plan_id").eq("id", user!.id).single(),
  ]);

  return (
    <div className="space-y-8">
      <header>
        <h1 className="font-display text-3xl font-bold tracking-tight">Plan & usage</h1>
        <p className="mt-2 text-mute">Upgrading with Razorpay will be switched on in the billing phase.</p>
      </header>
      <div className="grid gap-4 sm:grid-cols-2">
        {(plans ?? []).map((p) => {
          const current = p.id === profile?.plan_id;
          return (
            <section key={p.id} className={`rounded-2xl border p-6 ${current ? "border-hot bg-raised" : "border-line bg-surface"}`}>
              <div className="flex items-baseline justify-between">
                <h2 className="font-display text-xl font-semibold">{p.name}</h2>
                {current && <span className="text-sm text-hot">Current plan</span>}
              </div>
              <p className="mt-2 font-display text-3xl font-bold">{p.price_inr === 0 ? "Free" : `₹${p.price_inr}`}<span className="text-sm font-normal text-mute">{p.price_inr ? " / month" : ""}</span></p>
              <ul className="mt-4 space-y-1.5 text-sm text-mute">
                <li>{p.minutes_per_month} processing minutes</li>
                <li>{p.clips_per_month} clips</li>
                <li>{formatBytes(Number(p.storage_bytes))} storage</li>
              </ul>
            </section>
          );
        })}
      </div>
    </div>
  );
}

CLIPGENIUS_EOF
mkdir -p "./src/app/(app)/dashboard"
cat > "./src/app/(app)/dashboard/page.tsx" <<'CLIPGENIUS_EOF'
import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { formatBytes, formatDate } from "@/lib/format";
import Meter from "@/components/Meter";

export const dynamic = "force-dynamic";

const STATUS_STYLE: Record<string, string> = {
  ready: "text-ok", failed: "text-bad", processing: "text-glow", uploading: "text-glow", draft: "text-mute",
};

export default async function DashboardPage() {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  const monthStart = new Date(); monthStart.setUTCDate(1); monthStart.setUTCHours(0, 0, 0, 0);

  const count = (table: string, f?: (q: any) => any) => {
    const q = supabase.from(table).select("*", { count: "exact", head: true });
    return (f ? f(q) : q).then((r: { count: number | null }) => r.count ?? 0);
  };

  const [videos, clips, saved, published, failed, sizes, profile, ledger, recent] = await Promise.all([
    count("videos"),
    count("clips"),
    count("clips", (q) => q.eq("saved", true)),
    count("publish_jobs", (q) => q.eq("status", "published")),
    count("jobs", (q) => q.eq("status", "failed")),
    supabase.from("videos").select("size_bytes"),
    supabase.from("profiles").select("plan_id, plans(*)").eq("id", user!.id).single(),
    supabase.from("usage_ledger").select("kind, amount").gte("created_at", monthStart.toISOString()),
    supabase.from("projects").select("id, title, status, created_at").order("created_at", { ascending: false }).limit(5),
  ]);

  const plan = profile.data?.plans as unknown as {
    name: string; minutes_per_month: number; clips_per_month: number; storage_bytes: number;
  } | null;
  const storageUsed = (sizes.data ?? []).reduce((s, v) => s + Number(v.size_bytes), 0);
  const sum = (kind: string) => (ledger.data ?? []).filter((l) => l.kind === kind).reduce((s, l) => s + Number(l.amount), 0);

  const stats = [
    { label: "Videos uploaded", value: videos },
    { label: "Clips generated", value: clips },
    { label: "Saved clips", value: saved },
    { label: "Published", value: published },
    { label: "Failed jobs", value: failed, bad: failed > 0 },
  ];

  return (
    <div className="space-y-12">
      <header>
        <h1 className="font-display text-3xl font-bold tracking-tight md:text-4xl">Your clips, at a glance</h1>
        <p className="mt-2 text-mute">{plan?.name ?? "Free"} plan · usage resets on the 1st of each month.</p>
      </header>

      <section aria-label="Totals" className="grid grid-cols-2 gap-x-6 gap-y-8 sm:grid-cols-3 lg:grid-cols-5">
        {stats.map((s) => (
          <div key={s.label} className="border-l-2 border-line pl-4">
            <p className={`font-display text-4xl font-bold tabular-nums ${s.bad ? "text-bad" : ""}`}>{s.value}</p>
            <p className="mt-1 text-sm text-mute">{s.label}</p>
          </div>
        ))}
      </section>

      <section aria-label="Usage" className="rounded-2xl border border-line bg-surface p-6">
        <h2 className="font-display text-lg font-semibold">Plan usage</h2>
        <div className="mt-5 space-y-6">
          <Meter label="Processing minutes" used={sum("processing_minutes")} limit={plan?.minutes_per_month ?? 0} />
          <Meter label="Clips this month" used={sum("clips")} limit={plan?.clips_per_month ?? 0} />
          <Meter label="Storage" used={storageUsed} limit={Number(plan?.storage_bytes ?? 0)} format={formatBytes} />
        </div>
      </section>

      <section aria-label="Recent projects">
        <div className="flex items-baseline justify-between">
          <h2 className="font-display text-lg font-semibold">Recent projects</h2>
          <Link href="/projects" className="text-sm text-mute underline underline-offset-4 hover:text-ink">View all</Link>
        </div>
        {(recent.data ?? []).length === 0 ? (
          <p className="mt-4 rounded-xl border border-dashed border-line p-6 text-mute">
            No projects yet. Video upload arrives in the next phase; your projects will show up here.
          </p>
        ) : (
          <ul className="mt-4 divide-y divide-line rounded-xl border border-line bg-surface">
            {recent.data!.map((p) => (
              <li key={p.id} className="flex items-center justify-between gap-4 px-5 py-4">
                <span className="truncate">{p.title}</span>
                <span className="shrink-0 text-sm">
                  <span className={STATUS_STYLE[p.status]}>{p.status}</span>
                  <span className="ml-3 text-mute">{formatDate(p.created_at)}</span>
                </span>
              </li>
            ))}
          </ul>
        )}
      </section>
    </div>
  );
}

CLIPGENIUS_EOF
mkdir -p "./src/app/(app)"
cat > "./src/app/(app)/layout.tsx" <<'CLIPGENIUS_EOF'
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { Sidebar, MobileBar } from "@/components/Nav";

export default async function AppLayout({ children }: { children: React.ReactNode }) {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");

  const { data: profile } = await supabase
    .from("profiles").select("email, plan_id, plans(name)").eq("id", user.id).single();
  const plan = profile?.plans as unknown as { name: string } | null;

  return (
    <>
      <Sidebar email={profile?.email ?? user.email ?? ""} planName={plan?.name ?? "Free"} />
      <div className="md:pl-60">
        <main className="mx-auto max-w-5xl px-5 pb-28 pt-8 md:px-10 md:pb-16 md:pt-12">{children}</main>
      </div>
      <MobileBar />
    </>
  );
}

CLIPGENIUS_EOF
mkdir -p "./src/app/(app)/projects"
cat > "./src/app/(app)/projects/page.tsx" <<'CLIPGENIUS_EOF'
import { createClient } from "@/lib/supabase/server";
import { formatDate } from "@/lib/format";

export const dynamic = "force-dynamic";

export default async function ProjectsPage() {
  const supabase = await createClient();
  const { data: projects } = await supabase
    .from("projects").select("id, title, status, created_at").order("created_at", { ascending: false });

  return (
    <div className="space-y-8">
      <header>
        <h1 className="font-display text-3xl font-bold tracking-tight">Projects</h1>
        <p className="mt-2 text-mute">Every video you process becomes a project with its clips.</p>
      </header>
      {(projects ?? []).length === 0 ? (
        <p className="rounded-xl border border-dashed border-line p-8 text-mute">
          Nothing here yet. Uploading videos is the next phase to be built.
        </p>
      ) : (
        <ul className="divide-y divide-line rounded-xl border border-line bg-surface">
          {projects!.map((p) => (
            <li key={p.id} className="flex items-center justify-between gap-4 px-5 py-4">
              <span className="truncate">{p.title}</span>
              <span className="shrink-0 text-sm text-mute">{p.status} · {formatDate(p.created_at)}</span>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}

CLIPGENIUS_EOF
mkdir -p "./src/app/(auth)/login"
cat > "./src/app/(auth)/login/page.tsx" <<'CLIPGENIUS_EOF'
import AuthForm from "@/components/AuthForm";
export default function LoginPage() { return <AuthForm mode="login" />; }

CLIPGENIUS_EOF
mkdir -p "./src/app/(auth)/signup"
cat > "./src/app/(auth)/signup/page.tsx" <<'CLIPGENIUS_EOF'
import AuthForm from "@/components/AuthForm";
export default function SignupPage() { return <AuthForm mode="signup" />; }

CLIPGENIUS_EOF
mkdir -p "./src/app/auth/callback"
cat > "./src/app/auth/callback/route.ts" <<'CLIPGENIUS_EOF'
import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";

export async function GET(request: Request) {
  const { searchParams, origin } = new URL(request.url);
  const code = searchParams.get("code");
  if (code) {
    const supabase = await createClient();
    const { error } = await supabase.auth.exchangeCodeForSession(code);
    if (!error) return NextResponse.redirect(`${origin}/dashboard`);
  }
  return NextResponse.redirect(`${origin}/login`);
}

CLIPGENIUS_EOF
mkdir -p "./src/app"
cat > "./src/app/globals.css" <<'CLIPGENIUS_EOF'
@tailwind base;
@tailwind components;
@tailwind utilities;

:root { color-scheme: dark; }

body {
  @apply bg-night text-ink font-sans antialiased;
  background-image:
    radial-gradient(60rem 30rem at 85% -10%, rgba(255, 77, 141, 0.14), transparent 60%),
    radial-gradient(50rem 28rem at -10% 110%, rgba(255, 179, 71, 0.08), transparent 60%);
  background-attachment: fixed;
}

:focus-visible { outline: 2px solid #FFB347; outline-offset: 2px; }

@keyframes reveal { from { transform: scaleX(0); } to { transform: scaleX(1); } }
.meter-fill { transform-origin: left; animation: reveal 700ms cubic-bezier(.2,.8,.2,1) both; }

@media (prefers-reduced-motion: reduce) {
  .meter-fill { animation: none; }
}

CLIPGENIUS_EOF
mkdir -p "./src/app"
cat > "./src/app/layout.tsx" <<'CLIPGENIUS_EOF'
import type { Metadata } from "next";
import { Bricolage_Grotesque, Instrument_Sans } from "next/font/google";
import "./globals.css";

const display = Bricolage_Grotesque({ subsets: ["latin"], variable: "--font-display" });
const body = Instrument_Sans({ subsets: ["latin"], variable: "--font-body" });

export const metadata: Metadata = {
  title: "ClipGenius AI",
  description: "Turn long videos into short clips that get watched.",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className={`${display.variable} ${body.variable}`}>
      <body>{children}</body>
    </html>
  );
}

CLIPGENIUS_EOF
mkdir -p "./src/app"
cat > "./src/app/page.tsx" <<'CLIPGENIUS_EOF'
import { redirect } from "next/navigation";

export default function Home() {
  redirect("/dashboard");
}

CLIPGENIUS_EOF
mkdir -p "./src/components"
cat > "./src/components/AuthForm.tsx" <<'CLIPGENIUS_EOF'
"use client";

import { useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";

export default function AuthForm({ mode }: { mode: "login" | "signup" }) {
  const router = useRouter();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const isSignup = mode === "signup";

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true); setError(null); setNotice(null);
    const supabase = createClient();

    if (isSignup) {
      const { data, error } = await supabase.auth.signUp({
        email, password,
        options: { emailRedirectTo: `${window.location.origin}/auth/callback` },
      });
      if (error) setError(error.message);
      else if (!data.session) setNotice("Check your email to confirm your account, then log in.");
      else router.push("/dashboard");
    } else {
      const { error } = await supabase.auth.signInWithPassword({ email, password });
      if (error) setError(error.message);
      else { router.push("/dashboard"); router.refresh(); }
    }
    setBusy(false);
  }

  async function google() {
    setError(null);
    const { error } = await createClient().auth.signInWithOAuth({
      provider: "google",
      options: { redirectTo: `${window.location.origin}/auth/callback` },
    });
    if (error) setError(error.message);
  }

  const field = "w-full rounded-lg border border-line bg-surface px-3.5 py-3 text-ink placeholder:text-mute/60 focus:border-hot";

  return (
    <main className="mx-auto flex min-h-screen max-w-md flex-col justify-center px-6 py-12">
      <p className="font-display text-3xl font-bold tracking-tight">
        Clip<span className="bg-brand bg-clip-text text-transparent">Genius</span> AI
      </p>
      <h1 className="mt-8 font-display text-2xl font-semibold">
        {isSignup ? "Create your account" : "Welcome back"}
      </h1>
      <p className="mt-1 text-mute">
        {isSignup ? "Start with the free plan. No card needed." : "Log in to pick up your projects."}
      </p>

      <form onSubmit={onSubmit} className="mt-8 space-y-4">
        <label className="block">
          <span className="mb-1.5 block text-sm text-mute">Email</span>
          <input className={field} type="email" required autoComplete="email" value={email} onChange={(e) => setEmail(e.target.value)} />
        </label>
        <label className="block">
          <span className="mb-1.5 block text-sm text-mute">Password</span>
          <input className={field} type="password" required minLength={8} autoComplete={isSignup ? "new-password" : "current-password"} value={password} onChange={(e) => setPassword(e.target.value)} />
        </label>
        {error && <p role="alert" className="text-sm text-bad">{error}</p>}
        {notice && <p role="status" className="text-sm text-ok">{notice}</p>}
        <button disabled={busy} className="w-full rounded-lg bg-brand py-3 font-semibold text-night disabled:opacity-60">
          {busy ? "Please wait…" : isSignup ? "Create account" : "Log in"}
        </button>
      </form>

      <div className="my-6 flex items-center gap-3 text-sm text-mute"><span className="h-px flex-1 bg-line" />or<span className="h-px flex-1 bg-line" /></div>
      <button onClick={google} type="button" className="w-full rounded-lg border border-line bg-surface py-3 font-medium hover:bg-raised">
        Continue with Google
      </button>

      <p className="mt-8 text-sm text-mute">
        {isSignup ? "Already have an account? " : "New here? "}
        <Link className="text-ink underline underline-offset-4" href={isSignup ? "/login" : "/signup"}>
          {isSignup ? "Log in" : "Create an account"}
        </Link>
      </p>
    </main>
  );
}

CLIPGENIUS_EOF
mkdir -p "./src/components"
cat > "./src/components/Meter.tsx" <<'CLIPGENIUS_EOF'
// A usage bar drawn like a timeline: 20 ticks, filled up to the used share.
export default function Meter({ label, used, limit, format }: {
  label: string; used: number; limit: number; format?: (n: number) => string;
}) {
  const fmt = format ?? ((n: number) => String(Math.round(n)));
  const pct = limit > 0 ? Math.min(100, (used / limit) * 100) : 0;
  const hot = pct >= 90;
  return (
    <div>
      <div className="mb-2 flex items-baseline justify-between text-sm">
        <span>{label}</span>
        <span className="text-mute">{fmt(used)} of {fmt(limit)}</span>
      </div>
      <div className="relative h-3 overflow-hidden rounded-sm bg-raised"
        role="progressbar" aria-label={label} aria-valuemin={0} aria-valuemax={100} aria-valuenow={Math.round(pct)}>
        <div className={`meter-fill absolute inset-y-0 left-0 ${hot ? "bg-bad" : "bg-brand"}`} style={{ width: `${pct}%` }} />
        <div className="absolute inset-0" style={{ backgroundImage: "repeating-linear-gradient(90deg, transparent 0 calc(5% - 1px), #12111C calc(5% - 1px) 5%)" }} />
      </div>
    </div>
  );
}

CLIPGENIUS_EOF
mkdir -p "./src/components"
cat > "./src/components/Nav.tsx" <<'CLIPGENIUS_EOF'
"use client";

import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { LayoutDashboard, Film, CreditCard, LogOut } from "lucide-react";
import { createClient } from "@/lib/supabase/client";

const ITEMS = [
  { href: "/dashboard", label: "Dashboard", Icon: LayoutDashboard },
  { href: "/projects", label: "Projects", Icon: Film },
  { href: "/billing", label: "Plan & usage", Icon: CreditCard },
];

export function Sidebar({ email, planName }: { email: string; planName: string }) {
  const pathname = usePathname();
  const router = useRouter();

  async function signOut() {
    await createClient().auth.signOut();
    router.push("/login");
    router.refresh();
  }

  return (
    <aside className="fixed inset-y-0 left-0 hidden w-60 flex-col border-r border-line bg-surface/70 p-5 backdrop-blur md:flex">
      <p className="font-display text-xl font-bold tracking-tight">
        Clip<span className="bg-brand bg-clip-text text-transparent">Genius</span> AI
      </p>
      <nav className="mt-10 space-y-1" aria-label="Main">
        {ITEMS.map(({ href, label, Icon }) => {
          const active = pathname.startsWith(href);
          return (
            <Link key={href} href={href} aria-current={active ? "page" : undefined}
              className={`flex items-center gap-3 rounded-lg px-3 py-2.5 text-sm transition-colors ${active ? "bg-raised text-ink" : "text-mute hover:bg-raised/60 hover:text-ink"}`}>
              <Icon size={18} /> {label}
            </Link>
          );
        })}
      </nav>
      <div className="mt-auto border-t border-line pt-4">
        <p className="truncate text-sm">{email}</p>
        <p className="text-xs text-mute">{planName} plan</p>
        <button onClick={signOut} className="mt-3 flex items-center gap-2 text-sm text-mute hover:text-ink">
          <LogOut size={16} /> Log out
        </button>
      </div>
    </aside>
  );
}

export function MobileBar() {
  const pathname = usePathname();
  return (
    <nav aria-label="Main" className="fixed inset-x-0 bottom-0 z-20 flex border-t border-line bg-surface/95 backdrop-blur md:hidden">
      {ITEMS.map(({ href, label, Icon }) => {
        const active = pathname.startsWith(href);
        return (
          <Link key={href} href={href} aria-current={active ? "page" : undefined}
            className={`flex flex-1 flex-col items-center gap-1 py-3 text-xs ${active ? "text-ink" : "text-mute"}`}>
            <Icon size={20} /> {label}
          </Link>
        );
      })}
    </nav>
  );
}

CLIPGENIUS_EOF
mkdir -p "./src/lib"
cat > "./src/lib/format.ts" <<'CLIPGENIUS_EOF'
export function formatBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  const units = ["KB", "MB", "GB", "TB"];
  let v = bytes / 1024, i = 0;
  while (v >= 1024 && i < units.length - 1) { v /= 1024; i++; }
  return `${v.toFixed(v >= 10 ? 0 : 1)} ${units[i]}`;
}

export function formatDate(iso: string): string {
  return new Date(iso).toLocaleDateString("en-IN", { day: "numeric", month: "short", year: "numeric" });
}

CLIPGENIUS_EOF
mkdir -p "./src/lib/supabase"
cat > "./src/lib/supabase/client.ts" <<'CLIPGENIUS_EOF'
import { createBrowserClient } from "@supabase/ssr";

export function createClient() {
  return createBrowserClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
  );
}

CLIPGENIUS_EOF
mkdir -p "./src/lib/supabase"
cat > "./src/lib/supabase/server.ts" <<'CLIPGENIUS_EOF'
import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";

export async function createClient() {
  const cookieStore = await cookies();
  return createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll: () => cookieStore.getAll(),
        setAll: (list) => {
          try {
            list.forEach(({ name, value, options }) => cookieStore.set(name, value, options));
          } catch {
            // Called from a Server Component; middleware refreshes the session instead.
          }
        },
      },
    }
  );
}

CLIPGENIUS_EOF
mkdir -p "./src"
cat > "./src/middleware.ts" <<'CLIPGENIUS_EOF'
import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";

const PUBLIC_PATHS = ["/login", "/signup", "/auth"];

export async function middleware(request: NextRequest) {
  let response = NextResponse.next({ request });

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll: () => request.cookies.getAll(),
        setAll: (list) => {
          list.forEach(({ name, value }) => request.cookies.set(name, value));
          response = NextResponse.next({ request });
          list.forEach(({ name, value, options }) => response.cookies.set(name, value, options));
        },
      },
    }
  );

  const { data: { user } } = await supabase.auth.getUser();
  const path = request.nextUrl.pathname;
  const isPublic = PUBLIC_PATHS.some((p) => path.startsWith(p));

  if (!user && !isPublic) {
    const url = request.nextUrl.clone();
    url.pathname = "/login";
    return NextResponse.redirect(url);
  }
  if (user && (path === "/login" || path === "/signup")) {
    const url = request.nextUrl.clone();
    url.pathname = "/dashboard";
    return NextResponse.redirect(url);
  }
  return response;
}

export const config = {
  matcher: ["/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)"],
};

CLIPGENIUS_EOF
mkdir -p "./supabase/migrations"
cat > "./supabase/migrations/0001_schema.sql" <<'CLIPGENIUS_EOF'
-- ClipGenius AI: core schema (Phase 1)

-- Plans (limits are placeholders; edit freely)
create table public.plans (
  id text primary key,
  name text not null,
  price_inr integer not null default 0,
  minutes_per_month integer not null,
  clips_per_month integer not null,
  storage_bytes bigint not null,
  sort_order integer not null default 0
);
insert into public.plans values
  ('free',    'Free',    0,    30,   10,   1073741824,   1),
  ('starter', 'Starter', 799,  300,  100,  21474836480,  2),
  ('pro',     'Pro',     1999, 1200, 500,  107374182400, 3),
  ('creator', 'Creator', 4499, 3000, 1500, 322122547200, 4);

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  full_name text,
  plan_id text not null default 'free' references public.plans(id),
  razorpay_customer_id text,
  created_at timestamptz not null default now()
);

create table public.projects (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  title text not null,
  status text not null default 'draft' check (status in ('draft','uploading','processing','ready','failed')),
  created_at timestamptz not null default now()
);
create index on public.projects (user_id, created_at desc);

create table public.videos (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  project_id uuid not null references public.projects(id) on delete cascade,
  source text not null default 'upload' check (source in ('upload','youtube_owned')),
  storage_key text,
  original_filename text,
  size_bytes bigint not null default 0,
  duration_seconds numeric,
  status text not null default 'pending' check (status in ('pending','uploaded','processing','ready','failed')),
  created_at timestamptz not null default now()
);
create index on public.videos (project_id);

create table public.transcripts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  video_id uuid not null references public.videos(id) on delete cascade,
  language text,
  words jsonb not null default '[]',   -- [{w, start, end}]
  created_at timestamptz not null default now()
);

create table public.caption_presets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.profiles(id) on delete cascade, -- null = built-in
  name text not null,
  config jsonb not null default '{}',
  created_at timestamptz not null default now()
);

create table public.clips (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  project_id uuid not null references public.projects(id) on delete cascade,
  video_id uuid not null references public.videos(id) on delete cascade,
  start_seconds numeric not null,
  end_seconds numeric not null,
  engagement_score integer check (engagement_score between 0 and 100),
  explanation text,
  caption_preset_id uuid references public.caption_presets(id),
  caption_overrides jsonb not null default '{}',
  render_key text,
  status text not null default 'suggested' check (status in ('suggested','rendering','ready','failed')),
  saved boolean not null default false,
  metadata jsonb not null default '{}',  -- titles, hooks, hashtags, etc.
  created_at timestamptz not null default now(),
  check (end_seconds > start_seconds)
);
create index on public.clips (project_id);

create table public.jobs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  project_id uuid references public.projects(id) on delete cascade,
  video_id uuid references public.videos(id) on delete cascade,
  clip_id uuid references public.clips(id) on delete cascade,
  kind text not null check (kind in ('transcribe','analyze','render','publish')),
  status text not null default 'queued' check (status in ('queued','running','succeeded','failed','canceled')),
  progress integer not null default 0 check (progress between 0 and 100),
  error text,
  created_at timestamptz not null default now(),
  finished_at timestamptz
);
create index on public.jobs (user_id, created_at desc);

create table public.social_accounts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  platform text not null check (platform in ('youtube','instagram','facebook','tiktok')),
  external_id text not null,
  display_name text,
  created_at timestamptz not null default now(),
  unique (user_id, platform, external_id)
);
-- Tokens live in a separate table with NO policies: only the service role can touch it.
create table public.social_account_tokens (
  social_account_id uuid primary key references public.social_accounts(id) on delete cascade,
  token_encrypted text not null,
  expires_at timestamptz
);

create table public.publish_jobs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  clip_id uuid not null references public.clips(id) on delete cascade,
  social_account_id uuid not null references public.social_accounts(id) on delete cascade,
  title text,
  description text,
  scheduled_at timestamptz,
  approved_at timestamptz,            -- must be set by the user before any publish
  status text not null default 'draft' check (status in ('draft','scheduled','publishing','published','failed')),
  external_url text,
  created_at timestamptz not null default now()
);

create table public.subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  plan_id text not null references public.plans(id),
  razorpay_subscription_id text unique,
  status text not null default 'active',
  current_period_end timestamptz,
  created_at timestamptz not null default now()
);

create table public.usage_ledger (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  kind text not null check (kind in ('processing_minutes','clips')),
  amount numeric not null,
  job_id uuid references public.jobs(id) on delete set null,
  created_at timestamptz not null default now()
);
create index on public.usage_ledger (user_id, kind, created_at desc);

-- Auto-create a profile for every new auth user
create function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, email, full_name)
  values (new.id, new.email, coalesce(new.raw_user_meta_data->>'full_name', split_part(new.email, '@', 1)));
  return new;
end $$;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- Row level security
alter table public.plans enable row level security;
alter table public.profiles enable row level security;
alter table public.projects enable row level security;
alter table public.videos enable row level security;
alter table public.transcripts enable row level security;
alter table public.caption_presets enable row level security;
alter table public.clips enable row level security;
alter table public.jobs enable row level security;
alter table public.social_accounts enable row level security;
alter table public.social_account_tokens enable row level security;
alter table public.publish_jobs enable row level security;
alter table public.subscriptions enable row level security;
alter table public.usage_ledger enable row level security;

create policy "plans readable" on public.plans for select to authenticated using (true);
create policy "own profile read" on public.profiles for select using (id = auth.uid());
create policy "own profile name update" on public.profiles for update using (id = auth.uid()) with check (id = auth.uid());

-- Full control of own rows
create policy "own rows" on public.projects for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "own rows" on public.videos for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "own rows" on public.clips for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "own rows" on public.publish_jobs for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "own rows" on public.social_accounts for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "own presets + built-ins read" on public.caption_presets for select using (user_id = auth.uid() or user_id is null);
create policy "own presets write" on public.caption_presets for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Read-only for users (written by backend/service role)
create policy "own read" on public.transcripts for select using (user_id = auth.uid());
create policy "own read" on public.jobs for select using (user_id = auth.uid());
create policy "own read" on public.subscriptions for select using (user_id = auth.uid());
create policy "own read" on public.usage_ledger for select using (user_id = auth.uid());
-- social_account_tokens: intentionally no policies.

-- Users may only edit their display name; plan changes come from billing webhooks (service role).
revoke update on public.profiles from authenticated;
grant update (full_name) on public.profiles to authenticated;

CLIPGENIUS_EOF
mkdir -p "."
cat > "./tailwind.config.ts" <<'CLIPGENIUS_EOF'
import type { Config } from "tailwindcss";

const config: Config = {
  content: ["./src/**/*.{ts,tsx}"],
  theme: {
    extend: {
      colors: {
        night: "#12111C",
        surface: "#1B1A29",
        raised: "#232236",
        line: "#2E2C45",
        ink: "#EDEBF7",
        mute: "#9A97B8",
        hot: "#FF4D8D",
        glow: "#FFB347",
        ok: "#4ADE9A",
        bad: "#FF6B6B",
      },
      fontFamily: {
        display: ["var(--font-display)", "system-ui", "sans-serif"],
        sans: ["var(--font-body)", "system-ui", "sans-serif"],
      },
      backgroundImage: {
        brand: "linear-gradient(90deg, #FF4D8D 0%, #FFB347 100%)",
      },
    },
  },
  plugins: [],
};
export default config;

CLIPGENIUS_EOF
mkdir -p "."
cat > "./tsconfig.json" <<'CLIPGENIUS_EOF'
{
  "compilerOptions": {
    "target": "ES2022", "lib": ["dom", "dom.iterable", "esnext"], "allowJs": false, "skipLibCheck": true,
    "strict": true, "noEmit": true, "esModuleInterop": true, "module": "esnext", "moduleResolution": "bundler",
    "resolveJsonModule": true, "isolatedModules": true, "jsx": "preserve", "incremental": true,
    "plugins": [{ "name": "next" }], "paths": { "@/*": ["./src/*"] }
  },
  "include": ["next-env.d.ts", "**/*.ts", "**/*.tsx", ".next/types/**/*.ts"],
  "exclude": ["node_modules"]
}

CLIPGENIUS_EOF
echo "Done. Next: cd clipgenius && cp .env.example .env.local, fill it in, then npm install && npm run dev"
