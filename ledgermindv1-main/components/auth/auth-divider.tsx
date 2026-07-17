import { Separator } from "@/components/ui/separator"

interface AuthDividerProps {
  label: string
}

export function AuthDivider({ label }: AuthDividerProps) {
  return (
    <div className="relative my-6">
      <Separator />
      <span className="absolute left-1/2 top-1/2 -translate-x-1/2 -translate-y-1/2 bg-card px-3 text-xs font-medium text-muted-foreground">
        {label}
      </span>
    </div>
  )
}
