import type React from "react"
import { Logo } from "@/components/brand/logo"
import {
  WifiOff,
  CreditCard,
  LineChart,
  ShieldCheck,
} from "lucide-react"

interface AuthLayoutProps {
  children: React.ReactNode
}

const highlights = [
  {
    icon: WifiOff,
    title: "Offline-first POS",
    description: "Never lose a sale when connectivity drops.",
  },
  {
    icon: CreditCard,
    title: "Paystack ready",
    description: "Payments reconcile automatically with every transaction.",
  },
  {
    icon: LineChart,
    title: "Live inventory",
    description: "Track stock, branches, and revenue in one place.",
  },
  {
    icon: ShieldCheck,
    title: "Built for Ghana",
    description: "Designed around the realities of African retail.",
  },
]

export function AuthLayout({ children }: AuthLayoutProps) {
  return (
    <div className="relative grid min-h-screen w-full lg:grid-cols-2">
      <div className="relative hidden flex-col justify-between overflow-hidden bg-muted p-10 text-foreground lg:flex">
        <div className="aurora absolute inset-0 opacity-60" />
        <div className="pointer-events-none absolute -right-20 -top-20 h-[28rem] w-[28rem] rounded-full bg-primary/10 blur-3xl" />
        <div className="pointer-events-none absolute -bottom-24 -left-24 h-[24rem] w-[24rem] rounded-full bg-primary/10 blur-3xl" />

        <div className="relative z-10">
          <Logo />
        </div>

        <div className="relative z-10 max-w-md">
          <h2 className="text-3xl font-bold tracking-tight">
            Retail intelligence built for African chains.
          </h2>
          <p className="mt-3 text-base text-muted-foreground">
            LedgerMind connects your point of sale, payments, and inventory into one clear operating system.
          </p>

          <div className="mt-10 grid gap-4">
            {highlights.map((item) => (
              <div
                key={item.title}
                className="flex items-start gap-4 rounded-xl border border-border/60 bg-background/80 p-4 shadow-sm backdrop-blur-sm"
              >
                <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-lg bg-primary/10">
                  <item.icon className="h-5 w-5 text-primary" />
                </div>
                <div>
                  <p className="font-semibold text-foreground">{item.title}</p>
                  <p className="text-sm text-muted-foreground">
                    {item.description}
                  </p>
                </div>
              </div>
            ))}
          </div>
        </div>

        <p className="relative z-10 text-sm text-muted-foreground">
          © {new Date().getFullYear()} LedgerMind. All rights reserved.
        </p>
      </div>

      <div className="relative flex flex-col items-center justify-center bg-background p-6 sm:p-12">
        <div className="mb-8 lg:hidden">
          <Logo />
        </div>
        <div className="w-full max-w-md">{children}</div>
      </div>
    </div>
  )
}
