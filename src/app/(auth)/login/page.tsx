import Link from "next/link";
import { Store } from "lucide-react";

export default function LoginPage() {
  return (
    <div className="min-h-screen flex items-center justify-center bg-slate-50 p-4">
      <div className="w-full max-w-md bg-white rounded-2xl border border-slate-200 p-8 shadow-xs">
        <div className="flex flex-col items-center mb-6">
          <Link href="/" className="flex items-center gap-2 font-bold text-xl text-slate-900 mb-2">
            <Store className="w-6 h-6 text-blue-600" />
            <span>LOJIX</span>
          </Link>
          <h1 className="text-2xl font-bold text-slate-900">Iniciar Sessão</h1>
          <p className="text-sm text-slate-500 mt-1">Aceda ao painel de controlo da sua loja</p>
        </div>

        <form className="space-y-4">
          <div>
            <label className="block text-xs font-semibold uppercase text-slate-700 mb-1" htmlFor="email">
              E-mail
            </label>
            <input
              id="email"
              type="email"
              required
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
              placeholder="••••••••"
              className="w-full px-3.5 py-2.5 rounded-xl border border-slate-300 text-sm focus:outline-hidden focus:ring-2 focus:ring-blue-500/20 focus:border-blue-500"
            />
          </div>

          <button
            type="submit"
            className="w-full bg-blue-600 hover:bg-blue-700 text-white font-medium py-2.5 rounded-xl text-sm transition-colors shadow-xs"
          >
            Entrar
          </button>
        </form>

        <p className="text-center text-xs text-slate-500 mt-6">
          Ainda não tem loja?{" "}
          <Link href="/register" className="text-blue-600 font-semibold hover:underline">
            Criar conta grátis
          </Link>
        </p>
      </div>
    </div>
  );
}
