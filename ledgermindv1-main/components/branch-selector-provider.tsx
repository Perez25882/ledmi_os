"use client"

import * as React from "react"
import { useRouter } from "next/navigation"
import { SELECTED_BRANCH_COOKIE } from "@/lib/supabase/selected-branch-cookie"

export interface BranchOption {
  id: string
  name: string
}

interface BranchContextValue {
  /** Currently selected branch id, or `null` for "All Branches". */
  selectedBranchId: string | null
  /** Branches the user can switch between. */
  branches: BranchOption[]
  /** Whether the user is allowed to use "All Branches". */
  canAccessAll: boolean
  /** Update the selection, persist it, and refresh server data. */
  selectBranch: (branchId: string | null) => void
}

const BranchContext = React.createContext<BranchContextValue | null>(null)

export function BranchProvider({
  initialSelectedBranchId,
  branches,
  canAccessAll,
  children,
}: {
  initialSelectedBranchId: string | null
  branches: BranchOption[]
  canAccessAll: boolean
  children: React.ReactNode
}) {
  const router = useRouter()
  const [selectedBranchId, setSelectedBranchId] = React.useState<string | null>(
    initialSelectedBranchId
  )

  const selectBranch = React.useCallback(
    (branchId: string | null) => {
      setSelectedBranchId(branchId)
      if (branchId) {
        document.cookie = `${SELECTED_BRANCH_COOKIE}=${branchId}; path=/; max-age=31536000; samesite=lax`
      } else {
        document.cookie = `${SELECTED_BRANCH_COOKIE}=; path=/; max-age=0; samesite=lax`
      }
      router.refresh()
    },
    [router]
  )

  const value = React.useMemo<BranchContextValue>(
    () => ({ selectedBranchId, branches, canAccessAll, selectBranch }),
    [selectedBranchId, branches, canAccessAll, selectBranch]
  )

  return <BranchContext.Provider value={value}>{children}</BranchContext.Provider>
}

export function useBranchContext(): BranchContextValue {
  const ctx = React.useContext(BranchContext)
  if (!ctx) {
    throw new Error("useBranchContext must be used within a BranchProvider")
  }
  return ctx
}
