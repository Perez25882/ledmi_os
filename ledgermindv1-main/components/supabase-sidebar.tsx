"use client"

import type React from "react"
import { usePathname } from "next/navigation"
import Link from "next/link"
import {
  Sidebar,
  SidebarContent,
  SidebarFooter,
  SidebarHeader,
  SidebarMenu,
  SidebarMenuButton,
  SidebarMenuItem,
} from "@/components/ui/sidebar"
import {
  Package,
  LayoutDashboard,
  ShoppingCart,
  BarChart3,
  Settings,
  Users,
  Sparkles,
  LogOut,
  RotateCcw,
  Clock,
  FileText,
  ScrollText,
  CreditCard,
  Server,
} from "lucide-react"
import { Button } from "@/components/ui/button"
import { Avatar, AvatarFallback } from "@/components/ui/avatar"
import { Badge } from "@/components/ui/badge"
import { Logo } from "@/components/brand/logo"
import { createBrowserClient } from "@supabase/ssr"
import { useRouter } from "next/navigation"
import { canAccessPage, type UserRoleContext } from "@/lib/supabase/permissions"

export function SupabaseSidebar({
  context,
}: {
  context: UserRoleContext
}) {
  const router = useRouter()
  const pathname = usePathname()
  const supabase = createBrowserClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
  )

  async function handleLogout() {
    await supabase.auth.signOut()
    router.push("/auth/login")
  }

  const initial = context.email ? context.email.charAt(0).toUpperCase() : "U"
  const roleName = context.roleName

  const navItems = [
    { page: "overview", href: "/dashboard/overview", label: "Overview", icon: LayoutDashboard },
    { page: "inventory", href: "/dashboard/inventory/supabase", label: "Inventory", icon: Package },
    { page: "sales", href: "/dashboard/sales", label: "Sales", icon: ShoppingCart },
    { page: "refunds", href: "/dashboard/refunds", label: "Refunds", icon: RotateCcw },
    { page: "shifts", href: "/dashboard/shifts", label: "Shifts", icon: Clock },
    { page: "catalog", href: "/dashboard/catalog", label: "Catalog", icon: BarChart3 },
    { page: "reports", href: "/dashboard/reports", label: "Reports", icon: FileText },
    { page: "logs", href: "/dashboard/logs", label: "Audit Logs", icon: ScrollText },
    { page: "ai", href: "/dashboard/ai-insights/supabase", label: "Ledmi AI", icon: Sparkles },
    { page: "users", href: "/dashboard/users", label: "Users", icon: Users },
    { page: "settings", href: "/dashboard/settings", label: "Settings", icon: Settings },
    { page: "subscription", href: "/dashboard/subscription", label: "Subscription", icon: CreditCard },
    { page: "system", href: "/dashboard/system", label: "System", icon: Server },
  ] as const

  return (
    <Sidebar>
      <SidebarHeader>
        <div className="px-2 py-2">
          <Logo />
        </div>
      </SidebarHeader>

      <SidebarContent>
        <SidebarMenu>
          {navItems.map((item) => {
            if (!canAccessPage(roleName, item.page)) return null
            return (
              <SidebarMenuItem key={item.href}>
                <SidebarMenuButton
                  asChild
                  isActive={pathname === item.href}
                >
                  <Link href={item.href} prefetch={true}>
                    <item.icon className="h-4 w-4" />
                    <span>{item.label}</span>
                  </Link>
                </SidebarMenuButton>
              </SidebarMenuItem>
            )
          })}
        </SidebarMenu>
      </SidebarContent>

      <SidebarFooter>
        <div className="flex items-center gap-3 px-2 py-2">
          <Avatar className="h-8 w-8">
            <AvatarFallback className="bg-primary text-primary-foreground text-sm">
              {initial}
            </AvatarFallback>
          </Avatar>
          <div className="flex-1 min-w-0">
            <p className="text-sm font-medium truncate">{context.email}</p>
            <Badge
              variant="secondary"
              className="text-[10px] px-1.5 py-0 h-4 capitalize"
            >
              {roleName}
            </Badge>
          </div>
          <Button
            variant="ghost"
            size="icon"
            className="h-8 w-8"
            onClick={handleLogout}
          >
            <LogOut className="h-4 w-4" />
          </Button>
        </div>
      </SidebarFooter>
    </Sidebar>
  )
}
