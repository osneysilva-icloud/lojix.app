"use client";

import { useState, useTransition, Suspense } from "react";
import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { Store, Loader2, AlertCircle } from "lucide-react";
import { createClient } from "@/lib/supabase/client";

function LoginForm() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const next = searchParams.get("next") || "/dashboard";

  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [isPending, startTransition] = useTransition();

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);

    const supabase = createClient();
    const { data, error: authError } = await supabase.auth.signInWithPassword({
      email: email.trim().toLowerCase(),
      password,
    });

    if (authError) {
      setError(
        authError.message === "Invalid login credentials"
          ? "E-mail ou palavra-passe inválidos."
          : `Erro ao iniciar sessão: ${authError.message}`
      );
      return;
    }

    if (data.user) {
      // Verificar se o utilizador é superadmin para redirecionar de acordo
      const { data: profile } = await supabase
        .from("profiles")
        .select("platform_role, status")
        .eq("id", data.user.id)
        .single();

      startTransition(() => {
        if (profile?.platform_role === "superadmin" && next === "/dashboard") {
          router.push("/superadmin");
        } else {
          router.push(next);
        }
        router.refresh();
      });
    }
  };

  return (
    <div className="w-full max-w-md bg-white rounded-2xl border border-slate-200 p-8 shadow-xs">
      <div className="flex flex-col items-center mb-6">
        <Link href="/" className="flex items-center gap-2 font-bold text-xl text-slate-900 mb-2">
          <Store className="w-6 h-6 text-blue-600" />
          <span>LOJIX</span>
        </Link>
        <h1 className="text-2xl font-bold text-slate-900">Iniciar Sessão</h1>
        <p className="text-sm text-slate-500 mt-1">Aceda ao painel de controlo da sua loja</p>
      </div>

      {error && (
        <div className="mb-4 p-3 rounded-xl bg-rose-50 border border-rose-200 text-rose-700 text-xs flex items-center gap-2">
          <AlertCircle className="w-4 h-4 shrink-0" />
          <span>{error}</span>
        </div>
      )}

      <form onSubmit={handleSubmit} className="space-y-4">
        <div>
          <label className="block text-xs font-semibold uppercase text-slate-700 mb-1" htmlFor="email">
            E-mail
          </label>
          <input
            id="email"
            type="email"
            required
            autoComplete="email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            placeholder="seu@email.com"
            className="w-full px-3.5 py-2.5 rounded-xl border border-slate-300 text-sm focus:outline-hidden focus:ring-2 focus:ring-blue-500/20 focus:border-blue-500"
          />
        </div>

        <div>
          <div className="flex items-center justify-between mb-1">
            <label className="block text-xs font-semibold uppercase text-slate-700" htmlFor="password">
              Palavra-passe
            </label>
          </div>
          <input
            id="password"
            type="password"
            required
            autoComplete="current-password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            placeholder="••••••••"
            className="w-full px-3.5 py-2.5 rounded-xl border border-slate-300 text-sm focus:outline-hidden focus:ring-2 focus:ring-blue-500/20 focus:border-blue-500"
          />
        </div>

        <button
          type="submit"
          disabled={isPending}
          className="w-full flex items-center justify-center gap-2 bg-blue-600 hover:bg-blue-700 disabled:opacity-70 text-white font-medium py-2.5 rounded-xl text-sm transition-colors shadow-xs"
        >
          {isPending ? (
            <>
              <Loader2 className="w-4 h-4 animate-spin" />
              <span>A entrar...</span>
            </>
          ) : (
            <span>Entrar</span>
          )}
        </button>
      </form>

      <p className="text-center text-xs text-slate-500 mt-6">
        Ainda não tem loja?{" "}
        <Link href="/register" className="text-blue-600 font-semibold hover:underline">
          Criar conta grátis
        </Link>
      </p>
    </div>
  );
}

export default function LoginPage() {
  return (
    <div className="min-h-screen flex items-center justify-center bg-slate-50 p-4">
      <Suspense fallback={<div className="text-sm text-slate-500">A carregar...</div>}>
        <LoginForm />
      </Suspense>
    </div>
  );
}
