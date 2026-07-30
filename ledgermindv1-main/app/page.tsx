"use client"

import Link from "next/link"
import { useState } from "react"
import { Button } from "@/components/ui/button"
import { Card, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Logo } from "@/components/brand/logo"
import {
  Package,
  CreditCard,
  Brain,
  ShieldCheck,
  Smartphone,
  ArrowRight,
  CheckCircle2,
  Menu,
  X,
  WifiOff,
  Store,
} from "lucide-react"

const features = [
  {
    icon: WifiOff,
    title: "Offline-first POS",
    description:
      "Keep selling even when the internet drops. Sales sync automatically when connectivity returns.",
  },
  {
    icon: CreditCard,
    title: "Paystack payments",
    description:
      "Accept mobile money and cards through Paystack. Every payment ties directly to inventory and sales.",
  },
  {
    icon: Package,
    title: "Live inventory",
    description:
      "Track stock across branches, get low-stock alerts, and know exactly what to reorder.",
  },
  {
    icon: Brain,
    title: "Ledmi AI insights",
    description:
      "Demand forecasts, stock-out warnings, and revenue trends grounded in your actual data.",
  },
  {
    icon: Store,
    title: "Multi-branch control",
    description:
      "One dashboard for every store. Compare branch performance and move stock where it sells.",
  },
  {
    icon: ShieldCheck,
    title: "Audit-ready records",
    description:
      "Every sale, payment, and stock change is logged. Reconcile faster and stay compliant.",
  },
]

const steps = [
  {
    step: "01",
    title: "Connect your POS",
    description:
      "Install the Flutter POS on your counter. It works offline from day one.",
  },
  {
    step: "02",
    title: "Sell and get paid",
    description:
      "Take orders, accept Paystack, and let inventory update automatically with every transaction.",
  },
  {
    step: "03",
    title: "Act on insights",
    description:
      "Open LedgerMind to see what is selling, what is running low, and where to focus next.",
  },
]

export default function HomePage() {
  const [mobileMenuOpen, setMobileMenuOpen] = useState(false)

  return (
    <div className="min-h-screen bg-background">
      {/* Header */}
      <header className="sticky top-0 z-50 border-b border-border bg-background/95 backdrop-blur-sm">
        <div className="container mx-auto px-4">
          <div className="flex h-16 items-center justify-between">
            <Logo />

            <nav className="hidden md:flex items-center gap-8 text-sm font-medium text-muted-foreground">
              <Link href="#features" className="hover:text-foreground transition-colors">
                Features
              </Link>
              <Link href="#how-it-works" className="hover:text-foreground transition-colors">
                How it works
              </Link>
              <Link href="/auth/login" className="hover:text-foreground transition-colors">
                Sign in
              </Link>
            </nav>

            <div className="hidden md:flex items-center gap-3">
              <Link href="/auth/login">
                <Button variant="outline" size="sm">
                  Sign In
                </Button>
              </Link>
              <Link href="/auth/sign-up">
                <Button size="sm">
                  Get Started
                  <ArrowRight className="ml-1.5 h-4 w-4" />
                </Button>
              </Link>
            </div>

            <button
              type="button"
              className="md:hidden p-2 text-foreground"
              onClick={() => setMobileMenuOpen(!mobileMenuOpen)}
              aria-label="Toggle menu"
            >
              {mobileMenuOpen ? <X className="h-5 w-5" /> : <Menu className="h-5 w-5" />}
            </button>
          </div>
        </div>

        {mobileMenuOpen && (
          <div className="md:hidden border-t border-border px-4 py-4 bg-background">
            <nav className="flex flex-col gap-3 text-sm font-medium">
              <Link href="#features" className="text-muted-foreground hover:text-foreground">
                Features
              </Link>
              <Link href="#how-it-works" className="text-muted-foreground hover:text-foreground">
                How it works
              </Link>
              <Link href="/auth/login" className="text-muted-foreground hover:text-foreground">
                Sign in
              </Link>
              <Link href="/auth/sign-up">
                <Button className="w-full">
                  Get Started
                  <ArrowRight className="ml-1.5 h-4 w-4" />
                </Button>
              </Link>
            </nav>
          </div>
        )}
      </header>

      {/* Hero */}
      <section className="relative overflow-hidden pt-16 pb-24 sm:pt-24 sm:pb-32">
        <div className="pointer-events-none absolute inset-0 -z-10">
          <div className="absolute top-0 left-1/2 -translate-x-1/2 h-[600px] w-[800px] rounded-full bg-primary/5 blur-3xl" />
          <div className="absolute top-24 right-0 h-[300px] w-[300px] rounded-full bg-primary/5 blur-3xl" />
        </div>

        <div className="container mx-auto px-4">
          <div className="mx-auto max-w-3xl text-center">
            <div className="inline-flex items-center gap-2 rounded-full border border-primary/20 bg-primary/10 px-3 py-1 text-sm font-medium text-primary mb-6">
              <Smartphone className="h-4 w-4" />
              Built for African retail chains
            </div>
            <h1 className="text-4xl sm:text-5xl lg:text-6xl font-bold tracking-tight text-foreground mb-6">
              Every sale. Every cedi.{" "}
              <span className="gradient-text">One clear view.</span>
            </h1>
            <p className="text-lg sm:text-xl text-muted-foreground mb-8 max-w-2xl mx-auto text-pretty">
              LedgerMind connects your point of sale, Paystack payments, and inventory into a single operating system designed for Ghanaian retail.
            </p>
            <div className="flex flex-col sm:flex-row items-center justify-center gap-3">
              <Link href="/auth/sign-up">
                <Button size="lg" className="px-8">
                  Start free trial
                  <ArrowRight className="ml-2 h-4 w-4" />
                </Button>
              </Link>
              <Link href="#how-it-works">
                <Button variant="outline" size="lg" className="px-8">
                  See how it works
                </Button>
              </Link>
            </div>
          </div>

          {/* Dashboard preview */}
          <div className="mt-16 sm:mt-20 mx-auto max-w-5xl">
            <Card className="border-border/60 shadow-xl overflow-hidden bg-card">
              <div className="p-4 sm:p-6">
                <div className="grid grid-cols-3 gap-4 mb-4">
                  <div className="rounded-lg bg-muted p-4">
                    <p className="text-xs text-muted-foreground">Today&apos;s revenue</p>
                    <p className="text-xl font-bold text-foreground mt-1">GHS 12,450</p>
                  </div>
                  <div className="rounded-lg bg-muted p-4">
                    <p className="text-xs text-muted-foreground">Transactions</p>
                    <p className="text-xl font-bold text-foreground mt-1">148</p>
                  </div>
                  <div className="rounded-lg bg-primary/10 p-4">
                    <p className="text-xs text-primary">Low stock alerts</p>
                    <p className="text-xl font-bold text-primary mt-1">3 items</p>
                  </div>
                </div>
                <div className="flex items-end gap-2 h-32 rounded-lg bg-muted p-4">
                  {[40, 65, 45, 80, 55, 90, 70].map((h, i) => (
                    <div
                      key={i}
                      className="flex-1 rounded-sm bg-primary/60"
                      style={{ height: `${h}%` }}
                    />
                  ))}
                </div>
              </div>
            </Card>
          </div>
        </div>
      </section>

      {/* Trust bar */}
      <section className="border-y border-border bg-muted/50">
        <div className="container mx-auto px-4 py-8">
          <div className="grid grid-cols-2 md:grid-cols-4 gap-4 text-center">
            {[
              "Offline-first",
              "Paystack native",
              "Real-time sync",
              "Bank-grade security",
            ].map((item) => (
              <div
                key={item}
                className="flex items-center justify-center gap-2 text-sm font-medium text-muted-foreground"
              >
                <CheckCircle2 className="h-4 w-4 text-primary" />
                {item}
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Features */}
      <section id="features" className="py-20 sm:py-28">
        <div className="container mx-auto px-4 max-w-6xl">
          <div className="text-center max-w-2xl mx-auto mb-14">
            <h2 className="text-3xl sm:text-4xl font-bold tracking-tight text-foreground mb-4">
              Everything you need to run a modern retail chain
            </h2>
            <p className="text-lg text-muted-foreground">
              From the checkout counter to the back office, LedgerMind keeps your operations in sync.
            </p>
          </div>

          <div className="grid sm:grid-cols-2 lg:grid-cols-3 gap-6">
            {features.map((feature) => (
              <Card
                key={feature.title}
                className="border-border/60 bg-card transition-colors hover:bg-muted/40"
              >
                <CardHeader>
                  <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-primary/10 mb-4">
                    <feature.icon className="h-5 w-5 text-primary" />
                  </div>
                  <CardTitle className="text-lg">{feature.title}</CardTitle>
                  <CardDescription>{feature.description}</CardDescription>
                </CardHeader>
              </Card>
            ))}
          </div>
        </div>
      </section>

      {/* How it works */}
      <section id="how-it-works" className="py-20 sm:py-28 bg-muted/30">
        <div className="container mx-auto px-4 max-w-5xl">
          <div className="text-center max-w-2xl mx-auto mb-14">
            <h2 className="text-3xl sm:text-4xl font-bold tracking-tight text-foreground mb-4">
              How it works
            </h2>
            <p className="text-lg text-muted-foreground">
              Get your stores online in hours, not weeks.
            </p>
          </div>

          <div className="grid md:grid-cols-3 gap-8">
            {steps.map((item) => (
              <div key={item.step} className="relative">
                <div className="text-4xl font-bold text-primary/20">{item.step}</div>
                <h3 className="text-xl font-semibold text-foreground mt-2 mb-2">
                  {item.title}
                </h3>
                <p className="text-muted-foreground leading-relaxed">
                  {item.description}
                </p>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* CTA */}
      <section className="py-20 sm:py-28">
        <div className="container mx-auto px-4">
          <div className="mx-auto max-w-4xl rounded-2xl bg-primary/5 border border-primary/10 p-8 sm:p-12 text-center">
            <h2 className="text-3xl sm:text-4xl font-bold tracking-tight text-foreground mb-4">
              Ready to stop guessing about your stock?
            </h2>
            <p className="text-lg text-muted-foreground mb-8 max-w-2xl mx-auto">
              Join retail chains using LedgerMind to reduce stockouts, speed up reconciliation, and grow revenue.
            </p>
            <Link href="/auth/sign-up">
              <Button size="lg" className="px-8">
                Get started today
                <ArrowRight className="ml-2 h-4 w-4" />
              </Button>
            </Link>
          </div>
        </div>
      </section>

      {/* Footer */}
      <footer className="border-t border-border bg-muted/30 py-12">
        <div className="container mx-auto px-4">
          <div className="flex flex-col md:flex-row items-center justify-between gap-6">
            <Logo />
            <div className="flex items-center gap-6 text-sm text-muted-foreground">
              <Link href="/auth/login" className="hover:text-foreground transition-colors">
                Sign in
              </Link>
              <Link href="/auth/sign-up" className="hover:text-foreground transition-colors">
                Get started
              </Link>
            </div>
          </div>
          <p className="mt-8 text-center text-sm text-muted-foreground">
            © {new Date().getFullYear()} LedgerMind. All rights reserved.
          </p>
        </div>
      </footer>
    </div>
  )
}
