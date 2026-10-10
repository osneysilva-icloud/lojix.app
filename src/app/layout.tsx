import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "LOJIX — Crie e faça a gestão da sua loja online",
  description:
    "Plataforma moderna para criar a sua loja online, gerir catálogo e vender facilmente via WhatsApp e canais digitais.",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="pt">
      <body className="antialiased min-h-screen flex flex-col">{children}</body>
    </html>
  );
}
