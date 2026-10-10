import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { ShieldCheck, Users, Store, CreditCard, ArrowLeft } from "lucide-react";
import Link from "next/link";
import type { Profile } from "@/types/database";

export default async function SuperadminPage() {
  const supabase = await createClient();

  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect("/login");
  }

  // Verificar se utilizador é superadmin
  const { data: profile } = await supabase
    .from("profiles")
    .select("platform_role, status")
    .eq("id", user.id)
    .single();

  const typedProfile = profile as Profile | null;
  if (!typedProfile || typedProfile.platform_role !== "superadmin" || typedProfile.status !== "active") {
    redirect("/dashboard");
  }

  // Contagens para o resumo da plataforma
  const [{ count: storesCount }, { count: usersCount }, { count: plansCount }] = await Promise.all([
    supabase.from("stores").select("*", { count: "exact", head: true }),
    supabase.from("profiles").select("*", { count: "exact", head: true }),
    supabase.from("plans").select("*", { count: "exact", head: true }),
  ]);

  return (
    <div className="min-h-screen bg-slate-900 text-white flex flex-col">
      {/* Topbar */}
      <header className="bg-slate-950 border-b border-slate-800 sticky top-0 z-30">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 h-16 flex items-center justify-between">
          <div className="flex items-center gap-3">
            <div className="w-8 h-8 rounded-lg bg-amber-500/20 text-amber-400 flex items-center justify-center font-bold">
              <ShieldCheck className="w-5 h-5" />
            </div>
            <span className="font-bold text-lg tracking-tight">LOJIX Superadmin Console</span>
          </div>

          <Link
            href="/dashboard"
            className="flex items-center gap-2 text-xs text-slate-400 hover:text-white transition-colors bg-slate-800 px-3 py-1.5 rounded-lg"
          >
            <ArrowLeft className="w-3.5 h-3.5" />
            <span>Voltar ao Dashboard</span>
          </Link>
        </div>
      </header>

      {/* Conteúdo */}
      <main className="flex-1 max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8 w-full">
        <div className="mb-8">
          <h1 className="text-2xl font-bold text-white">Visão Geral da Plataforma</h1>
          <p className="text-sm text-slate-400">Monitorização e gestão global de instâncias e recursos</p>
        </div>

        {/* Estatísticas */}
        <div className="grid grid-cols-1 sm:grid-cols-3 gap-6 mb-8">
          <div className="bg-slate-800/60 border border-slate-700/60 rounded-2xl p-6">
            <div className="flex items-center justify-between mb-4">
              <span className="text-xs uppercase font-semibold tracking-wider text-slate-400">Total de Lojas</span>
              <Store className="w-5 h-5 text-blue-400" />
            </div>
            <div className="text-3xl font-extrabold text-white">{storesCount ?? 0}</div>
          </div>

          <div className="bg-slate-800/60 border border-slate-700/60 rounded-2xl p-6">
            <div className="flex items-center justify-between mb-4">
              <span className="text-xs uppercase font-semibold tracking-wider text-slate-400">Utilizadores Registados</span>
              <Users className="w-5 h-5 text-emerald-400" />
            </div>
            <div className="text-3xl font-extrabold text-white">{usersCount ?? 0}</div>
          </div>

          <div className="bg-slate-800/60 border border-slate-700/60 rounded-2xl p-6">
            <div className="flex items-center justify-between mb-4">
              <span className="text-xs uppercase font-semibold tracking-wider text-slate-400">Planos Configurados</span>
              <CreditCard className="w-5 h-5 text-purple-400" />
            </div>
            <div className="text-3xl font-extrabold text-white">{plansCount ?? 0}</div>
          </div>
        </div>

        {/* Gestão rápida */}
        <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
          <div className="bg-slate-800/60 border border-slate-700/60 rounded-2xl p-6">
            <h2 className="text-lg font-bold mb-2">Configurações Globais</h2>
            <p className="text-sm text-slate-400 mb-4">
              Ajuste limites de plataforma, permissões de registo e chaves de integração.
            </p>
            <span className="inline-block text-xs bg-slate-700 text-slate-300 px-3 py-1.5 rounded-lg">
              Em conformidade com as migrações 0001 - 0005
            </span>
          </div>

          <div className="bg-slate-800/60 border border-slate-700/60 rounded-2xl p-6">
            <h2 className="text-lg font-bold mb-2">Auditoria e Segurança</h2>
            <p className="text-sm text-slate-400 mb-4">
              Logs imutáveis de ações administrativas e controlos de integridade de slugs reservados.
            </p>
            <span className="inline-block text-xs bg-slate-700 text-slate-300 px-3 py-1.5 rounded-lg">
              RLS Ativo e Isolado
            </span>
          </div>
        </div>
      </main>
    </div>
  );
}
