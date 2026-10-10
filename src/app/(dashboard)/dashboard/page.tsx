import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { Store, Plus, Package, ExternalLink, Settings } from "lucide-react";
import Link from "next/link";
import type { Store as StoreModel, Profile } from "@/types/database";

export default async function DashboardPage() {
  const supabase = await createClient();

  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect("/login");
  }

  // 1. Procurar perfil do utilizador
  const { data: profile } = await supabase
    .from("profiles")
    .select("*")
    .eq("id", user.id)
    .single();

  const typedProfile = profile as Profile | null;

  // 2. Procurar lojas do comerciante
  const { data: stores } = await supabase
    .from("stores")
    .select("*")
    .eq("owner_id", user.id)
    .neq("status", "archived")
    .order("created_at", { ascending: false });

  const merchantStores = (stores ?? []) as StoreModel[];

  return (
    <div className="min-h-screen bg-slate-50 flex flex-col">
      {/* Topbar */}
      <header className="bg-white border-b border-slate-200 sticky top-0 z-30">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 h-16 flex items-center justify-between">
          <div className="flex items-center gap-3">
            <Link href="/dashboard" className="flex items-center gap-2 font-bold text-lg text-slate-900">
              <Store className="w-5 h-5 text-blue-600" />
              <span>LOJIX Dashboard</span>
            </Link>
          </div>
          <div className="flex items-center gap-4 text-sm">
            <span className="text-slate-600">
              Olá, <strong className="text-slate-900">{typedProfile?.full_name || user.email}</strong>
            </span>
            {typedProfile?.platform_role === "superadmin" && (
              <Link
                href="/superadmin"
                className="text-xs bg-amber-100 text-amber-800 font-medium px-2.5 py-1 rounded-md hover:bg-amber-200 transition-colors"
              >
                Superadmin
              </Link>
            )}
          </div>
        </div>
      </header>

      {/* Conteúdo */}
      <main className="flex-1 max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8 w-full">
        <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 mb-8">
          <div>
            <h1 className="text-2xl font-bold text-slate-900">As Minhas Lojas</h1>
            <p className="text-sm text-slate-500">Faça a gestão dos seus produtos, definições e vendas</p>
          </div>

          <button className="flex items-center gap-2 bg-blue-600 hover:bg-blue-700 text-white text-sm font-medium px-4 py-2.5 rounded-xl transition-colors shadow-xs">
            <Plus className="w-4 h-4" />
            <span>Criar Nova Loja</span>
          </button>
        </div>

        {merchantStores.length === 0 ? (
          <div className="bg-white rounded-2xl border border-dashed border-slate-300 p-12 text-center">
            <div className="w-12 h-12 rounded-2xl bg-blue-50 text-blue-600 flex items-center justify-center mx-auto mb-4">
              <Store className="w-6 h-6" />
            </div>
            <h3 className="text-lg font-bold text-slate-900 mb-1">Ainda não tem nenhuma loja criada</h3>
            <p className="text-sm text-slate-500 max-w-md mx-auto mb-6">
              Comece agora criando a sua primeira montra online para expor produtos e receber pedidos.
            </p>
            <button className="inline-flex items-center gap-2 bg-blue-600 hover:bg-blue-700 text-white text-sm font-medium px-5 py-2.5 rounded-xl transition-colors shadow-xs">
              <Plus className="w-4 h-4" />
              <span>Criar a Primeira Loja</span>
            </button>
          </div>
        ) : (
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
            {merchantStores.map((st) => (
              <div
                key={st.id}
                className="bg-white rounded-2xl border border-slate-200 p-6 flex flex-col justify-between hover:shadow-xs transition-shadow"
              >
                <div>
                  <div className="flex items-start justify-between mb-4">
                    <span className="font-bold text-lg text-slate-900">{st.name}</span>
                    <span
                      className={`text-xs font-semibold px-2.5 py-0.5 rounded-full capitalize ${
                        st.status === "published"
                          ? "bg-green-100 text-green-700"
                          : st.status === "suspended"
                          ? "bg-rose-100 text-rose-700"
                          : "bg-slate-100 text-slate-700"
                      }`}
                    >
                      {st.status}
                    </span>
                  </div>
                  <p className="text-xs text-slate-500 mb-4">
                    Subdomínio: <code className="bg-slate-100 px-1 py-0.5 rounded">{st.slug}.lojix.app</code>
                  </p>
                </div>

                <div className="pt-4 border-t border-slate-100 flex items-center justify-between text-sm">
                  <Link
                    href={`/dashboard/stores/${st.id}/products`}
                    className="flex items-center gap-1.5 text-slate-700 hover:text-blue-600 font-medium"
                  >
                    <Package className="w-4 h-4" />
                    <span>Produtos</span>
                  </Link>

                  <div className="flex items-center gap-2">
                    <Link
                      href={`/dashboard/stores/${st.id}/settings`}
                      className="p-2 text-slate-500 hover:text-slate-800 rounded-lg hover:bg-slate-50"
                      title="Definições da loja"
                    >
                      <Settings className="w-4 h-4" />
                    </Link>
                    <a
                      href={`/store/${st.slug}`}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="p-2 text-slate-500 hover:text-blue-600 rounded-lg hover:bg-slate-50"
                      title="Ver loja ao vivo"
                    >
                      <ExternalLink className="w-4 h-4" />
                    </a>
                  </div>
                </div>
              </div>
            ))}
          </div>
        )}
      </main>
    </div>
  );
}
