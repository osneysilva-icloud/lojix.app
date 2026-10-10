"use client";

import { useState } from "react";
import Link from "next/link";
import {
  Package,
  Settings,
  ExternalLink,
  Plus,
  CheckCircle2,
  AlertCircle,
  Eye,
  Globe,
  Trash2,
  ArrowLeft,
} from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import type { Store, StoreSettings, Product } from "@/types/database";

interface StoreBuilderProps {
  initialStore: Store;
  initialSettings: StoreSettings | null;
  initialProducts: Product[];
}

export function StoreBuilder({
  initialStore,
  initialSettings,
  initialProducts,
}: StoreBuilderProps) {
  const [store, setStore] = useState<Store>(initialStore);
  const [settings, setSettings] = useState<Partial<StoreSettings>>(initialSettings ?? {});
  const [products, setProducts] = useState<Product[]>(initialProducts);

  const [activeTab, setActiveTab] = useState<"settings" | "products" | "theme">("settings");

  // Estados de feedback
  const [isPending, setIsPending] = useState(false);
  const [saveSuccess, setSaveSuccess] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  // Estado para novo produto
  const [showNewProductModal, setShowNewProductModal] = useState(false);
  const [newProductName, setNewProductName] = useState("");
  const [newProductPrice, setNewProductPrice] = useState("");
  const [newProductDesc, setNewProductDesc] = useState("");
  const [newProductStock, setNewProductStock] = useState("10");

  // 1. Guardar definições da loja (WhatsApp, morada, banner)
  const handleSaveSettings = async (e: React.FormEvent) => {
    e.preventDefault();
    setErrorMessage(null);
    setSaveSuccess(false);
    setIsPending(true);

    try {
      const supabase = createClient();
      const { error } = await supabase
        .from("store_settings")
        .update({
          description: settings.description || null,
          whatsapp_number: settings.whatsapp_number || null,
          phone: settings.phone || null,
          contact_email: settings.contact_email || null,
          address: settings.address || null,
          banner_title: settings.banner_title || null,
          banner_subtitle: settings.banner_subtitle || null,
        })
        .eq("store_id", store.id);

      if (error) {
        setErrorMessage(`Erro ao guardar: ${error.message}`);
        return;
      }

      setSaveSuccess(true);
      setTimeout(() => setSaveSuccess(false), 3000);
    } finally {
      setIsPending(false);
    }
  };

  // 2. Alternar status da loja (Publicar / Despublicar)
  const handleTogglePublish = async () => {
    setErrorMessage(null);
    setIsPending(true);
    const newStatus = store.status === "published" ? "draft" : "published";

    try {
      const supabase = createClient();
      const { error } = await supabase
        .from("stores")
        .update({ status: newStatus })
        .eq("id", store.id);

      if (error) {
        setErrorMessage(`Erro ao alterar estado: ${error.message}`);
        return;
      }

      setStore((prev) => ({ ...prev, status: newStatus }));
    } finally {
      setIsPending(false);
    }
  };

  // 3. Criar novo produto
  const handleCreateProduct = async (e: React.FormEvent) => {
    e.preventDefault();
    setErrorMessage(null);

    const priceCents = Math.round(parseFloat(newProductPrice.replace(",", ".")) * 100);
    if (isNaN(priceCents) || priceCents < 0) {
      setErrorMessage("Introduza um preço válido.");
      return;
    }

    const slug = newProductName
      .toLowerCase()
      .normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "")
      .replace(/[^a-z0-9]+/g, "-")
      .slice(0, 30);

    const supabase = createClient();
    const { data: createdProduct, error } = await supabase
      .from("products")
      .insert({
        store_id: store.id,
        name: newProductName.trim(),
        slug,
        description: newProductDesc.trim() || null,
        price_cents: priceCents,
        stock_quantity: parseInt(newProductStock, 10) || 0,
        currency: store.currency,
        status: "published",
      })
      .select("*")
      .single();

    if (error) {
      setErrorMessage(`Erro ao criar produto: ${error.message}`);
      return;
    }

    setProducts((prev) => [...prev, createdProduct as Product]);
    setShowNewProductModal(false);
    setNewProductName("");
    setNewProductPrice("");
    setNewProductDesc("");
    setNewProductStock("10");
  };

  // 4. Eliminar produto
  const handleDeleteProduct = async (productId: string) => {
    if (!confirm("Tem a certeza que deseja eliminar este produto?")) return;

    const supabase = createClient();
    const { error } = await supabase.from("products").delete().eq("id", productId);

    if (error) {
      setErrorMessage(`Erro ao eliminar produto: ${error.message}`);
      return;
    }

    setProducts((prev) => prev.filter((p) => p.id !== productId));
  };

  return (
    <div className="max-w-6xl mx-auto py-8 px-4 sm:px-6">
      {/* Top Header */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 mb-6 pb-6 border-b border-slate-200">
        <div>
          <Link
            href="/dashboard"
            className="inline-flex items-center gap-1.5 text-xs font-semibold text-slate-500 hover:text-slate-800 mb-2 transition-colors"
          >
            <ArrowLeft className="w-3.5 h-3.5" />
            <span>Voltar ao Dashboard</span>
          </Link>
          <div className="flex items-center gap-3">
            <h1 className="text-2xl font-bold text-slate-900">{store.name}</h1>
            <span
              className={`text-xs font-bold px-2.5 py-0.5 rounded-full uppercase tracking-wider ${
                store.status === "published"
                  ? "bg-emerald-100 text-emerald-800 border border-emerald-200"
                  : "bg-amber-100 text-amber-800 border border-amber-200"
              }`}
            >
              {store.status === "published" ? "Publicada" : "Rascunho"}
            </span>
          </div>
          <p className="text-xs text-slate-500 mt-1">
            Endereço: <code className="bg-slate-100 px-1 py-0.5 rounded">{store.slug}.lojix.app</code>
          </p>
        </div>

        <div className="flex items-center gap-3">
          <a
            href={`/store/${store.slug}`}
            target="_blank"
            rel="noopener noreferrer"
            className="flex items-center gap-2 border border-slate-300 hover:bg-slate-50 text-slate-700 text-xs font-medium px-3.5 py-2 rounded-xl transition-colors shadow-xs"
          >
            <Eye className="w-4 h-4 text-slate-500" />
            <span>Ver Loja ao Vivo</span>
            <ExternalLink className="w-3 h-3 text-slate-400" />
          </a>

          <button
            onClick={handleTogglePublish}
            disabled={isPending}
            className={`flex items-center gap-2 text-xs font-medium px-4 py-2 rounded-xl transition-colors shadow-xs ${
              store.status === "published"
                ? "bg-amber-600 hover:bg-amber-700 text-white"
                : "bg-emerald-600 hover:bg-emerald-700 text-white"
            }`}
          >
            <Globe className="w-4 h-4" />
            <span>{store.status === "published" ? "Despublicar Loja" : "Publicar Loja"}</span>
          </button>
        </div>
      </div>

      {/* Alertas */}
      {errorMessage && (
        <div className="mb-6 p-4 rounded-xl bg-rose-50 border border-rose-200 text-rose-700 text-xs flex items-center gap-2">
          <AlertCircle className="w-4 h-4 shrink-0" />
          <span>{errorMessage}</span>
        </div>
      )}

      {saveSuccess && (
        <div className="mb-6 p-4 rounded-xl bg-emerald-50 border border-emerald-200 text-emerald-700 text-xs flex items-center gap-2">
          <CheckCircle2 className="w-4 h-4 shrink-0" />
          <span>Definições guardadas com sucesso!</span>
        </div>
      )}

      {/* Abas */}
      <div className="flex items-center gap-2 border-b border-slate-200 mb-8">
        <button
          onClick={() => setActiveTab("settings")}
          className={`flex items-center gap-2 px-4 py-2.5 text-sm font-semibold border-b-2 transition-colors -mb-px ${
            activeTab === "settings"
              ? "border-blue-600 text-blue-600"
              : "border-transparent text-slate-500 hover:text-slate-800"
          }`}
        >
          <Settings className="w-4 h-4" />
          <span>Definições da Loja</span>
        </button>

        <button
          onClick={() => setActiveTab("products")}
          className={`flex items-center gap-2 px-4 py-2.5 text-sm font-semibold border-b-2 transition-colors -mb-px ${
            activeTab === "products"
              ? "border-blue-600 text-blue-600"
              : "border-transparent text-slate-500 hover:text-slate-800"
          }`}
        >
          <Package className="w-4 h-4" />
          <span>Catálogo de Produtos ({products.length})</span>
        </button>
      </div>

      {/* Conteúdo da Aba Definições */}
      {activeTab === "settings" && (
        <div className="bg-white rounded-2xl border border-slate-200 p-8 shadow-xs">
          <form onSubmit={handleSaveSettings} className="space-y-6">
            <div>
              <h3 className="text-base font-bold text-slate-900 mb-1">Informações de Contacto & WhatsApp</h3>
              <p className="text-xs text-slate-500 mb-4">
                Configure o WhatsApp para onde as mensagens e pedidos dos clientes serão enviados.
              </p>

              <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                <div>
                  <label className="block text-xs font-semibold uppercase text-slate-700 mb-1" htmlFor="waNumber">
                    Número de WhatsApp (com indicativo)
                  </label>
                  <input
                    id="waNumber"
                    type="text"
                    value={settings.whatsapp_number || ""}
                    onChange={(e) => setSettings({ ...settings, whatsapp_number: e.target.value })}
                    placeholder="Ex: +258841234567"
                    className="w-full px-3.5 py-2.5 rounded-xl border border-slate-300 text-sm focus:outline-hidden focus:ring-2 focus:ring-blue-500/20 focus:border-blue-500"
                  />
                  <p className="mt-1 text-xs text-slate-400">Ex.: +258 (Moçambique), +55 (Brasil), etc.</p>
                </div>

                <div>
                  <label className="block text-xs font-semibold uppercase text-slate-700 mb-1" htmlFor="phone">
                    Telefone Alternativo
                  </label>
                  <input
                    id="phone"
                    type="text"
                    value={settings.phone || ""}
                    onChange={(e) => setSettings({ ...settings, phone: e.target.value })}
                    placeholder="Ex: +258821234567"
                    className="w-full px-3.5 py-2.5 rounded-xl border border-slate-300 text-sm focus:outline-hidden focus:ring-2 focus:ring-blue-500/20 focus:border-blue-500"
                  />
                </div>
              </div>
            </div>

            <div className="pt-6 border-t border-slate-100">
              <h3 className="text-base font-bold text-slate-900 mb-1">Apresentação & Localização</h3>
              <div className="grid grid-cols-1 gap-4 mt-4">
                <div>
                  <label className="block text-xs font-semibold uppercase text-slate-700 mb-1" htmlFor="desc">
                    Descrição Curta da Loja
                  </label>
                  <textarea
                    id="desc"
                    rows={2}
                    value={settings.description || ""}
                    onChange={(e) => setSettings({ ...settings, description: e.target.value })}
                    placeholder="Ex: A melhor loja de artigos desportivos e calçado em Maputo."
                    className="w-full px-3.5 py-2.5 rounded-xl border border-slate-300 text-sm focus:outline-hidden focus:ring-2 focus:ring-blue-500/20 focus:border-blue-500"
                  />
                </div>

                <div>
                  <label className="block text-xs font-semibold uppercase text-slate-700 mb-1" htmlFor="addr">
                    Endereço / Cidade
                  </label>
                  <input
                    id="addr"
                    type="text"
                    value={settings.address || ""}
                    onChange={(e) => setSettings({ ...settings, address: e.target.value })}
                    placeholder="Ex: Av. 24 de Julho, Maputo"
                    className="w-full px-3.5 py-2.5 rounded-xl border border-slate-300 text-sm focus:outline-hidden focus:ring-2 focus:ring-blue-500/20 focus:border-blue-500"
                  />
                </div>
              </div>
            </div>

            <div className="pt-6 border-t border-slate-100">
              <h3 className="text-base font-bold text-slate-900 mb-1">Banner Principal da Montra</h3>
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-4 mt-4">
                <div>
                  <label className="block text-xs font-semibold uppercase text-slate-700 mb-1" htmlFor="bTitle">
                    Título de Destaque
                  </label>
                  <input
                    id="bTitle"
                    type="text"
                    value={settings.banner_title || ""}
                    onChange={(e) => setSettings({ ...settings, banner_title: e.target.value })}
                    placeholder="Ex: Nova Coleção de Verão"
                    className="w-full px-3.5 py-2.5 rounded-xl border border-slate-300 text-sm focus:outline-hidden focus:ring-2 focus:ring-blue-500/20 focus:border-blue-500"
                  />
                </div>

                <div>
                  <label className="block text-xs font-semibold uppercase text-slate-700 mb-1" htmlFor="bSub">
                    Subtítulo do Banner
                  </label>
                  <input
                    id="bSub"
                    type="text"
                    value={settings.banner_subtitle || ""}
                    onChange={(e) => setSettings({ ...settings, banner_subtitle: e.target.value })}
                    placeholder="Ex: Até 30% de desconto em encomendas até domingo."
                    className="w-full px-3.5 py-2.5 rounded-xl border border-slate-300 text-sm focus:outline-hidden focus:ring-2 focus:ring-blue-500/20 focus:border-blue-500"
                  />
                </div>
              </div>
            </div>

            <div className="pt-6 border-t border-slate-100 flex justify-end">
              <button
                type="submit"
                disabled={isPending}
                className="flex items-center gap-2 bg-blue-600 hover:bg-blue-700 disabled:opacity-60 text-white font-medium px-5 py-2.5 rounded-xl text-sm transition-colors shadow-xs"
              >
                <span>Guardar Definições</span>
              </button>
            </div>
          </form>
        </div>
      )}

      {/* Conteúdo da Aba Produtos */}
      {activeTab === "products" && (
        <div>
          <div className="flex items-center justify-between mb-6">
            <div>
              <h3 className="text-lg font-bold text-slate-900">Produtos da Montra</h3>
              <p className="text-xs text-slate-500">Adicione artigos para os clientes visualizarem e encomendarem</p>
            </div>

            <button
              onClick={() => setShowNewProductModal(true)}
              className="flex items-center gap-2 bg-blue-600 hover:bg-blue-700 text-white text-xs font-medium px-4 py-2.5 rounded-xl transition-colors shadow-xs"
            >
              <Plus className="w-4 h-4" />
              <span>Adicionar Produto</span>
            </button>
          </div>

          {products.length === 0 ? (
            <div className="bg-white rounded-2xl border border-dashed border-slate-300 p-12 text-center">
              <div className="w-12 h-12 rounded-xl bg-blue-50 text-blue-600 flex items-center justify-center mx-auto mb-3">
                <Package className="w-6 h-6" />
              </div>
              <h4 className="font-bold text-slate-900 mb-1">Ainda não tem produtos adicionados</h4>
              <p className="text-xs text-slate-500 max-w-sm mx-auto mb-4">
                Crie o seu primeiro produto para começar a receber pedidos no WhatsApp.
              </p>
              <button
                onClick={() => setShowNewProductModal(true)}
                className="inline-flex items-center gap-1.5 bg-blue-600 hover:bg-blue-700 text-white text-xs font-medium px-4 py-2 rounded-xl transition-colors shadow-xs"
              >
                <Plus className="w-4 h-4" />
                <span>Adicionar Primeiro Produto</span>
              </button>
            </div>
          ) : (
            <div className="bg-white rounded-2xl border border-slate-200 overflow-hidden shadow-xs">
              <table className="w-full text-left text-sm">
                <thead className="bg-slate-50 border-b border-slate-200 text-xs uppercase font-semibold text-slate-600">
                  <tr>
                    <th className="py-3.5 px-4">Produto</th>
                    <th className="py-3.5 px-4">Preço</th>
                    <th className="py-3.5 px-4">Stock</th>
                    <th className="py-3.5 px-4">Estado</th>
                    <th className="py-3.5 px-4 text-right">Ações</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-slate-100">
                  {products.map((p) => {
                    const priceFormatted = (p.price_cents / 100).toLocaleString("pt-MZ", {
                      style: "currency",
                      currency: p.currency || store.currency,
                    });

                    return (
                      <tr key={p.id} className="hover:bg-slate-50/50">
                        <td className="py-3.5 px-4">
                          <div className="font-semibold text-slate-900">{p.name}</div>
                          {p.description && <div className="text-xs text-slate-400 truncate max-w-xs">{p.description}</div>}
                        </td>
                        <td className="py-3.5 px-4 font-bold text-slate-900">{priceFormatted}</td>
                        <td className="py-3.5 px-4 text-slate-600 text-xs">{p.stock_quantity ?? "Ilimitado"}</td>
                        <td className="py-3.5 px-4">
                          <span className="text-xs font-semibold px-2 py-0.5 rounded-full bg-emerald-50 text-emerald-700 border border-emerald-200">
                            Publicado
                          </span>
                        </td>
                        <td className="py-3.5 px-4 text-right">
                          <button
                            onClick={() => handleDeleteProduct(p.id)}
                            title="Eliminar produto"
                            className="p-1.5 text-slate-400 hover:text-rose-600 rounded-lg hover:bg-rose-50 transition-colors"
                          >
                            <Trash2 className="w-4 h-4" />
                          </button>
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          )}
        </div>
      )}

      {/* Modal Novo Produto */}
      {showNewProductModal && (
        <div className="fixed inset-0 z-50 bg-slate-950/40 backdrop-blur-xs flex items-center justify-center p-4">
          <div className="bg-white rounded-2xl border border-slate-200 p-6 max-w-md w-full shadow-xl">
            <h3 className="text-lg font-bold text-slate-900 mb-1">Novo Produto</h3>
            <p className="text-xs text-slate-500 mb-4">Adicione um novo item ao catálogo da sua loja</p>

            <form onSubmit={handleCreateProduct} className="space-y-4">
              <div>
                <label className="block text-xs font-semibold uppercase text-slate-700 mb-1" htmlFor="pName">
                  Nome do Artigo <span className="text-rose-500">*</span>
                </label>
                <input
                  id="pName"
                  type="text"
                  required
                  value={newProductName}
                  onChange={(e) => setNewProductName(e.target.value)}
                  placeholder="Ex: Ténis Nike Air Max"
                  className="w-full px-3.5 py-2.5 rounded-xl border border-slate-300 text-sm focus:outline-hidden focus:ring-2 focus:ring-blue-500/20 focus:border-blue-500"
                />
              </div>

              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="block text-xs font-semibold uppercase text-slate-700 mb-1" htmlFor="pPrice">
                    Preço ({store.currency}) <span className="text-rose-500">*</span>
                  </label>
                  <input
                    id="pPrice"
                    type="number"
                    step="0.01"
                    required
                    value={newProductPrice}
                    onChange={(e) => setNewProductPrice(e.target.value)}
                    placeholder="2500"
                    className="w-full px-3.5 py-2.5 rounded-xl border border-slate-300 text-sm focus:outline-hidden focus:ring-2 focus:ring-blue-500/20 focus:border-blue-500"
                  />
                </div>

                <div>
                  <label className="block text-xs font-semibold uppercase text-slate-700 mb-1" htmlFor="pStock">
                    Quantidade Stock
                  </label>
                  <input
                    id="pStock"
                    type="number"
                    value={newProductStock}
                    onChange={(e) => setNewProductStock(e.target.value)}
                    placeholder="10"
                    className="w-full px-3.5 py-2.5 rounded-xl border border-slate-300 text-sm focus:outline-hidden focus:ring-2 focus:ring-blue-500/20 focus:border-blue-500"
                  />
                </div>
              </div>

              <div>
                <label className="block text-xs font-semibold uppercase text-slate-700 mb-1" htmlFor="pDesc">
                  Descrição (Opcional)
                </label>
                <textarea
                  id="pDesc"
                  rows={2}
                  value={newProductDesc}
                  onChange={(e) => setNewProductDesc(e.target.value)}
                  placeholder="Tamanho 40-44, cores preto e branco..."
                  className="w-full px-3.5 py-2.5 rounded-xl border border-slate-300 text-sm focus:outline-hidden focus:ring-2 focus:ring-blue-500/20 focus:border-blue-500"
                />
              </div>

              <div className="pt-3 border-t border-slate-100 flex justify-end gap-2">
                <button
                  type="button"
                  onClick={() => setShowNewProductModal(false)}
                  className="px-4 py-2 rounded-xl text-xs font-medium text-slate-600 hover:bg-slate-100"
                >
                  Cancelar
                </button>
                <button
                  type="submit"
                  className="bg-blue-600 hover:bg-blue-700 text-white text-xs font-medium px-4 py-2 rounded-xl shadow-xs"
                >
                  Adicionar Artigo
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}
