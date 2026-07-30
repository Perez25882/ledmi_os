"use client"

import { Store } from "lucide-react"
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select"
import { useBranchContext } from "@/components/branch-selector-provider"

const ALL_BRANCHES_VALUE = "__all__"

export function BranchSelector() {
  const { selectedBranchId, branches, canAccessAll, selectBranch } = useBranchContext()

  // Users pinned to a single branch (managers/cashiers) get a read-only label.
  if (!canAccessAll) {
    const current = branches.find((b) => b.id === selectedBranchId) ?? branches[0]
    return (
      <div className="flex items-center gap-2 rounded-md border border-input bg-transparent px-3 h-8 text-sm text-muted-foreground">
        <Store className="size-4 opacity-70" />
        <span className="max-w-[10rem] truncate">{current?.name ?? "Branch"}</span>
      </div>
    )
  }

  const value = selectedBranchId ?? ALL_BRANCHES_VALUE

  function handleChange(next: string) {
    selectBranch(next === ALL_BRANCHES_VALUE ? null : next)
  }

  return (
    <Select value={value} onValueChange={handleChange}>
      <SelectTrigger size="sm" className="w-[12rem] gap-2" aria-label="Switch branch">
        <Store className="size-4 opacity-70" />
        <SelectValue placeholder="All Branches" />
      </SelectTrigger>
      <SelectContent>
        <SelectItem value={ALL_BRANCHES_VALUE}>All Branches</SelectItem>
        {branches.map((branch) => (
          <SelectItem key={branch.id} value={branch.id}>
            {branch.name}
          </SelectItem>
        ))}
      </SelectContent>
    </Select>
  )
}
