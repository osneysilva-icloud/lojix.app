"use client";

import { useState, useTransition, useEffect } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { Store, ArrowLeft, Loader2, AlertCircle, CheckCircle2, Sparkles } from "lucide-react";
import { createClient } from "@/lib/supabase/client";

function slugify(text: string): string {
  return text
    .toLowerCase()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 30);
}

export default function NewStorePage() {
  const router = useRouter();
  const [name, setName] = useState("");
  const [slug, setSlug] = useState("");
  const [autoSlug, setAutoSlug] = useState(true);
  const [templateKey, setTemplateKey] = useState("physical");
  const [currency, setCurrency] = useState("MZN");

  const [rawSlugStatus, setRawSlugStatus] = useState<"idle" | "checking" | "available" | "taken" | "invalid">("idle");
  const [error, setError] = useState<string | null>(null);
  const [isPending, startTransition] = useTransition();

  const slugStatus = slug.length < 3 ? "idle" : rawSlugStatus;

  const handleNameChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const newName = e.target.value;
    setName(newName);
    if (autoSlug) {
      setSlug(slugify(newName));
    }
  };

  const handleSlugChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    setAutoSlug(false);
    setSlug(e.target.value.toLowerCase().replace(/[^a-z0-9-]/g, ""));
  };

  // Verificar disponibilidade do slug
  useEffect(() => {
    if (!slug || slug.length < 3) return;

    let active = true;
    const timer = setTimeout(async () => {
      if (active) setRawSlugStatus("checking");

      const supabase = createClient();
      const { data, error: rpcError } = await supabase.rpc("slug_availability", {
        p_slug: slug,
      });

      if (!active) return;

      if (rpcError || !data) {
        setRawSlugStatus("idle");
      } else if (data === "available") {
        setRawSlugStatus("available");
      } else if (data === "taken" || data === "reserved") {
        setRawSlugStatus("taken");
      } else {
        setRawSlugStatus("invalid");
      }
    }, 400);

    return () => {
      active = false;
      clearTimeout(timer);
    };
  }, [slug]);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);

    if (slugStatus === "taken") {
      setError("Este endereço já está a ser utilizado por outra loja. Escolha outro.");
      return;
    }
    if (slugStatus === "invalid" || slug.length < 3) {
      setError("Endereço inválido. Deve ter entre 3 e 30 caracteres (apenas letras minúsculas, números e hífens).");
      return;
    }

    const supabase = createClient();
    const {
      data: { user },
    } = await supabase.auth.getUser();

    if (!user) {
      router.push("/login");
      return;
    }

    // Criar loja
    const { data: newStore, error: insertError } = await supabase
      .from("stores")
      .insert({
        owner_id: user.id,
        name: name.trim(),
        slug: slug.trim().toLowerCase(),
        template_key: templateKey,
        currency,
      })
      .select("id")
      .single();

    if (insertError) {
      setError(`Erro ao criar loja: ${insertError.message}`);
      return;
    }

    startTransition(() => {
      router.push(`/dashboard/stores/${newStore.id}`);
      router.refresh();
    });
  };

  return (
    <div className="min-h-screen bg-slate-50 py-10 px-4">
      <div className="max-w-2xl mx-auto">
        <Link
          href="/dashboard"
          className="inline-flex items-center gap-1.5 text-xs font-semibold text-slate-500 hover:text-slate-800 mb-6 transition-colors"
        >
          <ArrowLeft className="w-4 h-4" />
          <span>Voltar ao Dashboard</span>
        </Link>

        <div className="bg-white rounded-2xl border border-slate-200 p-8 shadow-xs">
          <div className="flex items-center gap-3 mb-6 pb-6 border-b border-slate-100">
            <div className="w-12 h-12 rounded-xl bg-blue-50 text-blue-600 flex items-center justify-center font-bold">
              <Store className="w-6 h-6" />
            </div>
            <div>
              <h1 className="text-xl font-bold text-slate-900">Criar Nova Loja</h1>
              <p className="text-xs text-slate-500">Configure o nome, modelo e endereço da sua nova montra online</p>
            </div>
          </div>

          {error && (
            <div className="mb-6 p-3.5 rounded-xl bg-rose-50 border border-rose-200 text-rose-700 text-xs flex items-center gap-2">
              <AlertCircle className="w-4 h-4 shrink-0" />
              <span>{error}</span>
            </div>
          )}

          <form onSubmit={handleSubmit} className="space-y-6">
            <div>
              <label htmlFor="name" className="block text-xs font-semibold uppercase text-slate-700 mb-1">
                Nome Comercial da Loja <span className="text-rose-500">*</span>
              </label>
              <input
                id="name"
                type="text"
                required
                maxLength={80}
                value={name}
                onChange={handleNameChange}
                placeholder="Ex: Boutique da Maria, EletroTech MZ"
                className="w-full px-3.5 py-2.5 rounded-xl border border-slate-300 text-sm focus:outline-hidden focus:ring-2 focus:ring-blue-500/20 focus:border-blue-500"
              />
            </div>

            <div>
              <div className="flex items-center justify-between mb-1">
                <label htmlFor="slug" className="block text-xs font-semibold uppercase text-slate-700">
                  Endereço da Loja (Subdomínio) <span className="text-rose-500">*</span>
                </label>
                <button
                  type="button"
                  onClick={() => {
                    const nextAuto = !autoSlug;
                    setAutoSlug(nextAuto);
                    if (nextAuto) setSlug(slugify(name));
                  }}
                  className="text-xs text-blue-600 hover:underline"
                >
                  {autoSlug ? "Personalizar endereço" : "Gerar automaticamente"}
                </button>
              </div>

              <div className="relative">
                <input
                  id="slug"
                  type="text"
                  required
                  value={slug}
                  onChange={handleSlugChange}
                  placeholder="nomedaloja"
                  className="w-full px-3.5 py-2.5 rounded-xl border border-slate-300 text-sm pr-10 focus:outline-hidden focus:ring-2 focus:ring-blue-500/20 focus:border-blue-500"
                />

                <div className="absolute right-3 top-1/2 -translate-y-1/2 text-xs">
                  {slugStatus === "checking" && <Loader2 className="w-4 h-4 animate-spin text-slate-400" />}
                  {slugStatus === "available" && <CheckCircle2 className="w-4 h-4 text-emerald-600" />}
                  {slugStatus === "taken" && <AlertCircle className="w-4 h-4 text-rose-500" />}
                </div>
              </div>

              <p className="mt-1.5 text-xs text-slate-500 flex items-center justify-between">
                <span>
                  O seu link será: <strong className="text-slate-800">{slug || "sua-loja"}.lojix.app</strong>
                </span>
                {slugStatus === "available" && <span className="text-emerald-600 font-semibold">Disponível!</span>}
                {slugStatus === "taken" && <span className="text-rose-600 font-semibold">Indisponível</span>}
              </p>
            </div>

            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
              <div>
                <label className="block text-xs font-semibold uppercase text-slate-700 mb-1">
                  Tipo de Loja
                </label>
                <select
                  value={templateKey}
                  onChange={(e) => setTemplateKey(e.target.value)}
                  className="w-full px-3.5 py-2.5 rounded-xl border border-slate-300 text-sm focus:outline-hidden focus:ring-2 focus:ring-blue-500/20 focus:border-blue-500 bg-white"
                >
                  <option value="physical">Produtos Físicos (Entrega / Retirada)</option>
                  <option value="digital">Produtos Digitais (Downloads / Cursos)</option>
                </select>
              </div>

              <div>
                <label className="block text-xs font-semibold uppercase text-slate-700 mb-1">
                  Moeda Principal
                </label>
                <select
                  value={currency}
                  onChange={(e) => setCurrency(e.target.value)}
                  className="w-full px-3.5 py-2.5 rounded-xl border border-slate-300 text-sm focus:outline-hidden focus:ring-2 focus:ring-blue-500/20 focus:border-blue-500 bg-white"
                >
                  <option value="MZN">Metical (MZN)</option>
                  <option value="USD">Dólar Americano (USD)</option>
                  <option value="EUR">Euro (EUR)</option>
                  <option value="BRL">Real Brasileiro (BRL)</option>
                  <option value="ZAR">Rand Sul-Africano (ZAR)</option>
                </select>
              </div>
            </div>

            <div className="pt-4 border-t border-slate-100 flex items-center justify-end gap-3">
              <Link
                href="/dashboard"
                className="px-4 py-2.5 rounded-xl text-sm font-medium text-slate-600 hover:bg-slate-100 transition-colors"
              >
                Cancelar
              </Link>
              <button
                type="submit"
                disabled={isPending || slugStatus === "taken"}
                className="flex items-center gap-2 bg-blue-600 hover:bg-blue-700 disabled:opacity-60 text-white font-medium px-5 py-2.5 rounded-xl text-sm transition-colors shadow-xs"
              >
                {isPending ? (
                  <>
                    <Loader2 className="w-4 h-4 animate-spin" />
                    <span>A criar loja...</span>
                  </>
                ) : (
                  <>
                    <Sparkles className="w-4 h-4" />
                    <span>Criar Loja</span>
                  </>
                )}
              </button>
            </div>
          </form>
        </div>
      </div>
    </div>
  );
}
