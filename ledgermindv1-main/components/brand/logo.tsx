import { Package } from "lucide-react"
import { cn } from "@/lib/utils"

interface LogoProps {
  className?: string
  iconClassName?: string
  showWordmark?: boolean
}

export function Logo({
  className,
  iconClassName,
  showWordmark = true,
}: LogoProps) {
  return (
    <div className={cn("flex items-center gap-2", className)}>
      <div className="flex h-9 w-9 items-center justify-center rounded-lg bg-primary/10">
        <Package className={cn("h-5 w-5 text-primary", iconClassName)} />
      </div>
      {showWordmark && (
        <span className="text-lg font-bold tracking-tight text-foreground">
          LedgerMind
        </span>
      )}
    </div>
  )
}
