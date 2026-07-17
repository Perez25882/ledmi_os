"use client"

import { useTransition } from "react"
import { Button } from "@/components/ui/button"

interface DeleteButtonProps {
  action: () => Promise<void>
  label?: string
}

export function DeleteButton({ action, label = "Delete" }: DeleteButtonProps) {
  const [isPending, startTransition] = useTransition()

  return (
    <Button
      variant="ghost"
      size="sm"
      disabled={isPending}
      onClick={() => startTransition(() => action())}
      className={label === "×" ? "h-4 w-4 p-0" : ""}
    >
      {label}
    </Button>
  )
}
