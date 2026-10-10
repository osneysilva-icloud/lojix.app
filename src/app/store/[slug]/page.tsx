import { notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { Store, MessageCircle, MapPin, Phone } from "lucide-react";
import type { Store as StoreModel, StoreSettings, Product } from "@/types/database";

interface StorePageProps {
  params: Promise<{ slug: string }>;
}

export default async function StoreFrontPage({ params }: StorePageProps) {
  const { slug } = await params;
  const supabase = await createClient();

  // 1. Procurar loja pelo slug
  const { data: store, error: storeError } = await supabase
    .from("stores")
    .select("*")
    .eq("slug", slug.toLowerCase())
    .single();

  if (storeError || !store) {
    notFound();
  }

  const typedStore = store as StoreModel;

  // 2. Procurar definições da loja
  const { data: settings } = await supabase
    .from("store_settings")
    .select("*")
    .eq("store_id", typedStore.id)
    .single();

  const typedSettings = (settings ?? {}) as Partial<StoreSettings>;

  // 3. Procurar produtos publicados e respetivas imagens
  const { data: products } = await supabase
    .from("products")
    .select(`
      *,
      product_images (
        media_files (path)
      )
    `)
    .eq("store_id", typedStore.id)
    .eq("status", "published")
    .order("created_at", { ascending: false });

  const typedProducts = (products ?? []) as (Product & {
    product_images?: { media_files?: { path?: string } | null }[];
  })[];

  return (
    <div className="min-h-screen flex flex-col bg-slate-50">
      {/* Cabeçalho da Loja */}
      <header className="bg-white border-b border-slate-200 sticky top-0 z-40">
        <div className="max-w-6xl mx-auto px-4 py-4 flex items-center justify-between">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-xl bg-blue-600 text-white flex items-center justify-center font-bold text-lg shadow-sm">
              <Store className="w-5 h-5" />
            </div>
            <div>
              <h1 className="font-bold text-xl text-slate-900">{typedStore.name}</h1>
              {typedSettings.description && (
                <p className="text-xs text-slate-500">{typedSettings.description}</p>
              )}
            </div>
          </div>

          {typedSettings.whatsapp_number && (
            <a
              href={`https://wa.me/${typedSettings.whatsapp_number.replace(/\D/g, "")}`}
              target="_blank"
              rel="noopener noreferrer"
              className="flex items-center gap-2 bg-emerald-600 hover:bg-emerald-700 text-white text-sm font-medium px-4 py-2 rounded-xl transition-colors shadow-xs"
            >
              <MessageCircle className="w-4 h-4" />
              <span>Falar no WhatsApp</span>
            </a>
          )}
        </div>
      </header>

      {/* Conteúdo Principal */}
      <main className="flex-1 max-w-6xl mx-auto px-4 py-8 w-full">
        {/* Banner */}
        {typedSettings.banner_title && (
          <div className="bg-blue-600 text-white rounded-3xl p-8 mb-8 shadow-sm">
            <h2 className="text-2xl sm:text-3xl font-extrabold mb-2">
              {typedSettings.banner_title}
            </h2>
            {typedSettings.banner_subtitle && (
              <p className="text-blue-100">{typedSettings.banner_subtitle}</p>
            )}
          </div>
        )}

        {/* Catálogo de Produtos */}
        <section>
          <div className="flex items-center justify-between mb-6">
            <h2 className="text-xl font-bold text-slate-900">Produtos</h2>
            <span className="text-sm text-slate-500">{typedProducts.length} itens</span>
          </div>

          {typedProducts.length === 0 ? (
            <div className="bg-white rounded-2xl border border-slate-200 p-12 text-center text-slate-500">
              <p>Ainda não há produtos disponíveis nesta montra.</p>
            </div>
          ) : (
            <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-6">
              {typedProducts.map((p) => {
                const formattedPrice = (p.price_cents / 100).toLocaleString("pt-MZ", {
                  style: "currency",
                  currency: p.currency || typedStore.currency || "MZN",
                });

                const mediaPath = p.product_images?.[0]?.media_files?.path;
                const imageUrl = mediaPath
                  ? supabase.storage.from("store-public").getPublicUrl(mediaPath).data.publicUrl
                  : null;

                return (
                  <article
                    key={p.id}
                    className="bg-white rounded-2xl border border-slate-200 overflow-hidden flex flex-col hover:shadow-md transition-shadow"
                  >
                    <div className="aspect-square bg-slate-100 flex items-center justify-center text-slate-400 overflow-hidden">
                      {imageUrl ? (
                        <img src={imageUrl} alt={p.name} className="w-full h-full object-cover" />
                      ) : (
                        <Store className="w-12 h-12" />
                      )}
                    </div>
                    <div className="p-4 flex flex-col flex-1">
                      <h3 className="font-semibold text-slate-900 text-base">{p.name}</h3>
                      {p.description && (
                        <p className="text-xs text-slate-500 mt-1 line-clamp-2">{p.description}</p>
                      )}
                      <div className="mt-auto pt-4 flex items-center justify-between">
                        <span className="font-bold text-lg text-slate-900">{formattedPrice}</span>
                        {typedSettings.whatsapp_number && (
                          <a
                            href={`https://wa.me/${typedSettings.whatsapp_number.replace(/\D/g, "")}?text=${encodeURIComponent(`Olá! Tenho interesse no produto: ${p.name}`)}`}
                            target="_blank"
                            rel="noopener noreferrer"
                            className="bg-slate-900 hover:bg-slate-800 text-white text-xs font-medium px-3 py-1.5 rounded-lg transition-colors"
                          >
                            Pedir
                          </a>
                        )}
                      </div>
                    </div>
                  </article>
                );
              })}
            </div>
          )}
        </section>
      </main>

      {/* Rodapé da Loja */}
      <footer className="bg-white border-t border-slate-200 py-6 mt-12">
        <div className="max-w-6xl mx-auto px-4 flex flex-col sm:flex-row items-center justify-between gap-4 text-xs text-slate-500">
          <div className="flex items-center gap-4">
            {typedSettings.address && (
              <span className="flex items-center gap-1">
                <MapPin className="w-3.5 h-3.5" />
                {typedSettings.address}
              </span>
            )}
            {typedSettings.phone && (
              <span className="flex items-center gap-1">
                <Phone className="w-3.5 h-3.5" />
                {typedSettings.phone}
              </span>
            )}
          </div>
          <p>Alimentado por <span className="font-semibold text-slate-700">LOJIX</span></p>
        </div>
      </footer>
    </div>
  );
}
