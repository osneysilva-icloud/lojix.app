"use client";

import { useState } from "react";
import {
  Store,
  MessageCircle,
  MapPin,
  Phone,
  Plus,
  Minus,
  X,
  Send,
  ShoppingBag,
} from "lucide-react";
import type { Store as StoreModel, StoreSettings, Product } from "@/types/database";

export interface ProductWithImages extends Product {
  imageUrl?: string | null;
}

interface StoreFrontViewProps {
  store: StoreModel;
  settings: Partial<StoreSettings>;
  products: ProductWithImages[];
}

export function StoreFrontView({ store, settings, products }: StoreFrontViewProps) {
  // Modal de pedido
  const [selectedProduct, setSelectedProduct] = useState<ProductWithImages | null>(null);
  const [quantity, setQuantity] = useState(1);
  const [customerName, setCustomerName] = useState("");
  const [customerPhone, setCustomerPhone] = useState("");
  const [deliveryAddress, setDeliveryAddress] = useState("");
  const [orderNotes, setOrderNotes] = useState("");

  const rawWhatsapp = settings.whatsapp_number?.replace(/\D/g, "") || "";

  const handleOpenOrderModal = (product: ProductWithImages) => {
    setSelectedProduct(product);
    setQuantity(1);
    setCustomerName("");
    setCustomerPhone("");
    setDeliveryAddress("");
    setOrderNotes("");
  };

  const handleCloseModal = () => {
    setSelectedProduct(null);
  };

  const handleSendWhatsappOrder = (e: React.FormEvent) => {
    e.preventDefault();
    if (!selectedProduct || !rawWhatsapp) return;

    const unitPrice = selectedProduct.price_cents / 100;
    const totalPrice = unitPrice * quantity;
    const currency = selectedProduct.currency || store.currency || "MZN";

    const formattedUnit = unitPrice.toLocaleString("pt-MZ", {
      style: "currency",
      currency,
    });
    const formattedTotal = totalPrice.toLocaleString("pt-MZ", {
      style: "currency",
      currency,
    });

    // Construção da mensagem formatada para o WhatsApp
    const messageLines = [
      `👋 *Olá! Gostaria de fazer o seguinte pedido:*`,
      ``,
      `🏪 *Loja:* ${store.name}`,
      `📦 *Artigo:* ${selectedProduct.name}`,
      `🔢 *Quantidade:* ${quantity}x`,
      `💰 *Preço Unitário:* ${formattedUnit}`,
      `💵 *TOTAL:* ${formattedTotal}`,
      ``,
      `👤 *Cliente:* ${customerName.trim()}`,
      customerPhone.trim() ? `📱 *Telefone:* ${customerPhone.trim()}` : null,
      deliveryAddress.trim() ? `📍 *Endereço de Entrega:* ${deliveryAddress.trim()}` : null,
      orderNotes.trim() ? `📝 *Observações:* ${orderNotes.trim()}` : null,
      ``,
      `_Pedido enviado através de lojix.app_`,
    ].filter(Boolean);

    const messageText = messageLines.join("\n");
    const whatsappUrl = `https://wa.me/${rawWhatsapp}?text=${encodeURIComponent(messageText)}`;

    // Abrir o WhatsApp
    window.open(whatsappUrl, "_blank", "noopener,noreferrer");

    // Fechar modal
    handleCloseModal();
  };

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
              <h1 className="font-bold text-xl text-slate-900">{store.name}</h1>
              {settings.description && (
                <p className="text-xs text-slate-500">{settings.description}</p>
              )}
            </div>
          </div>

          {rawWhatsapp && (
            <a
              href={`https://wa.me/${rawWhatsapp}`}
              target="_blank"
              rel="noopener noreferrer"
              className="flex items-center gap-2 bg-emerald-600 hover:bg-emerald-700 text-white text-xs sm:text-sm font-medium px-4 py-2 rounded-xl transition-colors shadow-xs"
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
        {settings.banner_title && (
          <div className="bg-blue-600 text-white rounded-3xl p-8 mb-8 shadow-sm">
            <h2 className="text-2xl sm:text-3xl font-extrabold mb-2">
              {settings.banner_title}
            </h2>
            {settings.banner_subtitle && (
              <p className="text-blue-100">{settings.banner_subtitle}</p>
            )}
          </div>
        )}

        {/* Catálogo de Produtos */}
        <section>
          <div className="flex items-center justify-between mb-6">
            <h2 className="text-xl font-bold text-slate-900">Produtos</h2>
            <span className="text-sm text-slate-500">{products.length} itens</span>
          </div>

          {products.length === 0 ? (
            <div className="bg-white rounded-2xl border border-slate-200 p-12 text-center text-slate-500">
              <p>Ainda não há produtos disponíveis nesta montra.</p>
            </div>
          ) : (
            <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-6">
              {products.map((p) => {
                const formattedPrice = (p.price_cents / 100).toLocaleString("pt-MZ", {
                  style: "currency",
                  currency: p.currency || store.currency || "MZN",
                });

                return (
                  <article
                    key={p.id}
                    className="bg-white rounded-2xl border border-slate-200 overflow-hidden flex flex-col hover:shadow-md transition-shadow"
                  >
                    <div className="aspect-square bg-slate-100 flex items-center justify-center text-slate-400 overflow-hidden">
                      {p.imageUrl ? (
                        <img src={p.imageUrl} alt={p.name} className="w-full h-full object-cover" />
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
                        <button
                          onClick={() => handleOpenOrderModal(p)}
                          className="bg-slate-900 hover:bg-slate-800 text-white text-xs font-medium px-4 py-2 rounded-xl transition-colors shadow-xs flex items-center gap-1.5"
                        >
                          <ShoppingBag className="w-3.5 h-3.5" />
                          <span>Pedir</span>
                        </button>
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
            {settings.address && (
              <span className="flex items-center gap-1">
                <MapPin className="w-3.5 h-3.5" />
                {settings.address}
              </span>
            )}
            {settings.phone && (
              <span className="flex items-center gap-1">
                <Phone className="w-3.5 h-3.5" />
                {settings.phone}
              </span>
            )}
          </div>
          <p>
            Alimentado por <span className="font-semibold text-slate-700">LOJIX</span>
          </p>
        </div>
      </footer>

      {/* Modal / Formulário de Pedido */}
      {selectedProduct && (
        <div className="fixed inset-0 z-50 bg-slate-950/50 backdrop-blur-xs flex items-center justify-center p-4">
          <div className="bg-white rounded-2xl border border-slate-200 max-w-lg w-full shadow-2xl overflow-hidden animate-in fade-in zoom-in-95 duration-150">
            {/* Cabeçalho do Modal */}
            <div className="p-4 sm:p-5 border-b border-slate-100 flex items-center justify-between">
              <div className="flex items-center gap-2">
                <ShoppingBag className="w-5 h-5 text-blue-600" />
                <h3 className="font-bold text-base text-slate-900">Finalizar Pedido</h3>
              </div>
              <button
                onClick={handleCloseModal}
                className="text-slate-400 hover:text-slate-600 p-1 rounded-lg hover:bg-slate-100 transition-colors"
              >
                <X className="w-5 h-5" />
              </button>
            </div>

            {/* Corpo do Formulário */}
            <form onSubmit={handleSendWhatsappOrder} className="p-4 sm:p-6 space-y-4">
              {/* Resumo do Produto & Quantidade */}
              <div className="bg-slate-50 p-4 rounded-xl border border-slate-200/60 flex items-center gap-4">
                {selectedProduct.imageUrl ? (
                  <img
                    src={selectedProduct.imageUrl}
                    alt={selectedProduct.name}
                    className="w-16 h-16 rounded-lg object-cover border border-slate-200 shrink-0"
                  />
                ) : (
                  <div className="w-16 h-16 rounded-lg bg-slate-200/60 flex items-center justify-center text-slate-400 shrink-0">
                    <Store className="w-8 h-8" />
                  </div>
                )}

                <div className="flex-1 min-w-0">
                  <h4 className="font-bold text-sm text-slate-900 truncate">{selectedProduct.name}</h4>
                  <p className="text-xs text-slate-500">
                    {(selectedProduct.price_cents / 100).toLocaleString("pt-MZ", {
                      style: "currency",
                      currency: selectedProduct.currency || store.currency || "MZN",
                    })}{" "}
                    / unidade
                  </p>

                  {/* Seletor de Quantidade */}
                  <div className="flex items-center gap-3 mt-2">
                    <span className="text-xs font-semibold text-slate-700">Qtd:</span>
                    <div className="flex items-center border border-slate-300 rounded-lg bg-white overflow-hidden">
                      <button
                        type="button"
                        onClick={() => setQuantity((q) => Math.max(1, q - 1))}
                        className="p-1 hover:bg-slate-100 text-slate-600 transition-colors"
                      >
                        <Minus className="w-3.5 h-3.5" />
                      </button>
                      <span className="px-3 text-xs font-bold text-slate-950 min-w-8 text-center">
                        {quantity}
                      </span>
                      <button
                        type="button"
                        onClick={() => setQuantity((q) => Math.min(99, q + 1))}
                        className="p-1 hover:bg-slate-100 text-slate-600 transition-colors"
                      >
                        <Plus className="w-3.5 h-3.5" />
                      </button>
                    </div>
                  </div>
                </div>

                {/* Subtotal Dinâmico */}
                <div className="text-right shrink-0">
                  <span className="text-xs text-slate-400 block">Total</span>
                  <span className="font-extrabold text-base text-blue-600">
                    {((selectedProduct.price_cents * quantity) / 100).toLocaleString("pt-MZ", {
                      style: "currency",
                      currency: selectedProduct.currency || store.currency || "MZN",
                    })}
                  </span>
                </div>
              </div>

              {/* Dados do Cliente */}
              <div>
                <label className="block text-xs font-semibold uppercase text-slate-700 mb-1" htmlFor="custName">
                  O seu Nome <span className="text-rose-500">*</span>
                </label>
                <input
                  id="custName"
                  type="text"
                  required
                  value={customerName}
                  onChange={(e) => setCustomerName(e.target.value)}
                  placeholder="Ex: Carlos Mário"
                  className="w-full px-3.5 py-2.5 rounded-xl border border-slate-300 text-sm focus:outline-hidden focus:ring-2 focus:ring-blue-500/20 focus:border-blue-500"
                />
              </div>

              <div>
                <label className="block text-xs font-semibold uppercase text-slate-700 mb-1" htmlFor="custPhone">
                  Seu Telefone / WhatsApp (Opcional)
                </label>
                <input
                  id="custPhone"
                  type="text"
                  value={customerPhone}
                  onChange={(e) => setCustomerPhone(e.target.value)}
                  placeholder="Ex: 84 123 4567"
                  className="w-full px-3.5 py-2.5 rounded-xl border border-slate-300 text-sm focus:outline-hidden focus:ring-2 focus:ring-blue-500/20 focus:border-blue-500"
                />
              </div>

              <div>
                <label className="block text-xs font-semibold uppercase text-slate-700 mb-1" htmlFor="custAddr">
                  Endereço / Local de Entrega
                </label>
                <input
                  id="custAddr"
                  type="text"
                  value={deliveryAddress}
                  onChange={(e) => setDeliveryAddress(e.target.value)}
                  placeholder="Ex: Bairro Central, Av. Eduardo Mondlane nº 10"
                  className="w-full px-3.5 py-2.5 rounded-xl border border-slate-300 text-sm focus:outline-hidden focus:ring-2 focus:ring-blue-500/20 focus:border-blue-500"
                />
              </div>

              <div>
                <label className="block text-xs font-semibold uppercase text-slate-700 mb-1" htmlFor="custNotes">
                  Observações (Opcional)
                </label>
                <textarea
                  id="custNotes"
                  rows={2}
                  value={orderNotes}
                  onChange={(e) => setOrderNotes(e.target.value)}
                  placeholder="Ex: Entregar após as 14h, troco para 500 MTn..."
                  className="w-full px-3.5 py-2.5 rounded-xl border border-slate-300 text-sm focus:outline-hidden focus:ring-2 focus:ring-blue-500/20 focus:border-blue-500"
                />
              </div>

              {/* Botão de Envio para o WhatsApp */}
              <div className="pt-2">
                <button
                  type="submit"
                  disabled={!rawWhatsapp}
                  className="w-full flex items-center justify-center gap-2 bg-emerald-600 hover:bg-emerald-700 disabled:opacity-50 text-white font-bold py-3 px-4 rounded-xl text-sm transition-all shadow-md hover:shadow-lg"
                >
                  <MessageCircle className="w-5 h-5" />
                  <span>Enviar Pedido para o WhatsApp</span>
                  <Send className="w-4 h-4 ml-1" />
                </button>
                {!rawWhatsapp && (
                  <p className="text-center text-xs text-rose-500 mt-2">
                    A loja ainda não configurou o número de WhatsApp nas definições.
                  </p>
                )}
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}
