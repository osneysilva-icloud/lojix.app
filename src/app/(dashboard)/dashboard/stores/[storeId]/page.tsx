import { notFound, redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { StoreBuilder } from "@/components/store/StoreBuilder";
import type { Store, StoreSettings, Product } from "@/types/database";

interface StoreManagementPageProps {
  params: Promise<{ storeId: string }>;
}

export default async function StoreManagementPage({ params }: StoreManagementPageProps) {
  const { storeId } = await params;
  const supabase = await createClient();

  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect("/login");
  }

  // 1. Procurar a loja
  const { data: store, error: storeError } = await supabase
    .from("stores")
    .select("*")
    .eq("id", storeId)
    .single();

  if (storeError || !store) {
    notFound();
  }

  // 2. Procurar definições da loja
  const { data: settings } = await supabase
    .from("store_settings")
    .select("*")
    .eq("store_id", storeId)
    .single();

  // 3. Procurar produtos da loja
  const { data: products } = await supabase
    .from("products")
    .select("*")
    .eq("store_id", storeId)
    .neq("status", "archived")
    .order("created_at", { ascending: false });

  return (
    <div className="min-h-screen bg-slate-50">
      <StoreBuilder
        initialStore={store as Store}
        initialSettings={settings as StoreSettings | null}
        initialProducts={(products ?? []) as Product[]}
      />
    </div>
  );
}
