import Link from "next/link";
import { Store, ShieldCheck, Zap, ArrowRight } from "lucide-react";

export default function HomePage() {
  return (
    <div className="flex flex-col min-h-screen">
      <header className="border-b border-slate-200 bg-white/80 backdrop-blur sticky top-0 z-50">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 h-16 flex items-center justify-between">
          <div className="flex items-center gap-2 font-bold text-xl text-slate-900">
            <Store className="w-6 h-6 text-blue-600" />
            <span>LOJIX</span>
          </div>
          <nav className="flex items-center gap-4">
            <Link
              href="/login"
              className="text-sm font-medium text-slate-700 hover:text-slate-900 transition-colors"
            >
              Entrar
            </Link>
            <Link
              href="/register"
              className="text-sm font-medium bg-blue-600 text-white px-4 py-2 rounded-lg hover:bg-blue-700 transition-colors shadow-sm"
            >
              Criar Loja Grátis
            </Link>
          </nav>
        </div>
      </header>

      <main className="flex-1">
        <section className="py-20 px-4 sm:px-6 lg:px-8 max-w-5xl mx-auto text-center">
          <span className="inline-block px-3 py-1 bg-blue-50 text-blue-700 rounded-full text-xs font-semibold uppercase tracking-wider mb-4">
            A sua montra digital em Moçambique e no mundo
          </span>
          <h1 className="text-4xl sm:text-6xl font-extrabold text-slate-950 tracking-tight leading-tight">
            Venda os seus produtos online de forma rápida, simples e profissional
          </h1>
          <p className="mt-6 text-lg sm:text-xl text-slate-600 max-w-2xl mx-auto leading-relaxed">
            Crie a sua loja com subdomínio próprio, adicione produtos físicos ou digitais e receba encomendas diretamente no seu WhatsApp.
          </p>
          <div className="mt-8 flex flex-col sm:flex-row items-center justify-center gap-4">
            <Link
              href="/register"
              className="w-full sm:w-auto flex items-center justify-center gap-2 bg-blue-600 text-white font-medium px-6 py-3.5 rounded-xl hover:bg-blue-700 transition-all shadow-md hover:shadow-lg"
            >
              Começar Agora
              <ArrowRight className="w-4 h-4" />
            </Link>
            <Link
              href="/login"
              className="w-full sm:w-auto flex items-center justify-center border border-slate-300 font-medium px-6 py-3.5 rounded-xl hover:bg-slate-50 transition-colors text-slate-800"
            >
              Aceder ao Painel
            </Link>
          </div>
        </section>

        <section className="py-16 bg-slate-50 border-t border-slate-200">
          <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 grid grid-cols-1 md:grid-cols-3 gap-8">
            <div className="bg-white p-6 rounded-2xl border border-slate-200 shadow-xs">
              <div className="w-10 h-10 rounded-xl bg-blue-100 text-blue-600 flex items-center justify-center mb-4">
                <Store className="w-5 h-5" />
              </div>
              <h3 className="text-lg font-bold text-slate-900 mb-2">Subdomínio Próprio</h3>
              <p className="text-sm text-slate-600">
                A sua loja terá um endereço limpo e direto: <code className="bg-slate-100 px-1 py-0.5 rounded text-xs">sualoja.lojix.app</code>.
              </p>
            </div>
            <div className="bg-white p-6 rounded-2xl border border-slate-200 shadow-xs">
              <div className="w-10 h-10 rounded-xl bg-green-100 text-green-600 flex items-center justify-center mb-4">
                <Zap className="w-5 h-5" />
              </div>
              <h3 className="text-lg font-bold text-slate-900 mb-2">Vendas por WhatsApp</h3>
              <p className="text-sm text-slate-600">
                Carrinho de compras intuitivo que formata o pedido e envia para o WhatsApp da sua empresa num clique.
              </p>
            </div>
            <div className="bg-white p-6 rounded-2xl border border-slate-200 shadow-xs">
              <div className="w-10 h-10 rounded-xl bg-purple-100 text-purple-600 flex items-center justify-center mb-4">
                <ShieldCheck className="w-5 h-5" />
              </div>
              <h3 className="text-lg font-bold text-slate-900 mb-2">Segurança e Controlo</h3>
              <p className="text-sm text-slate-600">
                Isolamento total multi-tenant garantido ao nível da base de dados com Row Level Security.
              </p>
            </div>
          </div>
        </section>
      </main>

      <footer className="border-t border-slate-200 py-8 bg-white text-center text-sm text-slate-500">
        <p>© {new Date().getFullYear()} LOJIX (lojix.app). Todos os direitos reservados.</p>
      </footer>
    </div>
  );
}
