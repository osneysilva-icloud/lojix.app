import { notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { StoreFrontView, type ProductWithImages } from "@/components/store/StoreFrontView";
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

  const productsWithImages: ProductWithImages[] = typedProducts.map((p) => {
    const mediaPath = p.product_images?.[0]?.media_files?.path;
    const imageUrl = mediaPath
      ? supabase.storage.from("store-public").getPublicUrl(mediaPath).data.publicUrl
      : null;

    return {
      ...p,
      imageUrl,
    };
  });

  return (
    <StoreFrontView
      store={typedStore}
      settings={typedSettings}
      products={productsWithImages}
    />
  );
}
