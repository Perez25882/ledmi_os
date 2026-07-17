"use client"

import { useState } from "react"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
  DropdownMenuSub,
  DropdownMenuSubTrigger,
  DropdownMenuSubContent,
  DropdownMenuRadioGroup,
  DropdownMenuRadioItem,
} from "@/components/ui/dropdown-menu"
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table"
import { MoreHorizontal, ShieldCheck, MailCheck, Trash2 } from "lucide-react"
import { updateMemberRole, removeMember } from "@/app/dashboard/users/actions"
import { useTransition } from "react"

export type BusinessMember = {
  user_id: string
  email: string
  role_id: string
  role_name: string
  created_at: string
}

export function UserManagementTable({
  members,
  currentUserId,
  roles,
  businessId,
}: {
  members: BusinessMember[]
  currentUserId: string
  roles: { id: string; name: string }[]
  businessId: string
}) {
  const [isPending, startTransition] = useTransition()
  const [message, setMessage] = useState<string | null>(null)

  const handleRoleChange = (userId: string, newRoleId: string) => {
    startTransition(async () => {
      try {
        await updateMemberRole(userId, newRoleId, businessId)
        setMessage("Role updated.")
      } catch (err) {
        setMessage(err instanceof Error ? err.message : "Failed to update role")
      }
    })
  }

  const handleRemove = (userId: string) => {
    if (!confirm("Remove this member from the business? They will lose dashboard access.")) return
    startTransition(async () => {
      try {
        await removeMember(userId, businessId)
        setMessage("Member removed.")
      } catch (err) {
        setMessage(err instanceof Error ? err.message : "Failed to remove member")
      }
    })
  }

  return (
    <div className="space-y-2">
      {message && (
        <div className="rounded-md bg-muted p-3 text-sm text-muted-foreground">
          {message}
        </div>
      )}
      <div className="rounded-md border bg-card">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Member</TableHead>
              <TableHead>Role</TableHead>
              <TableHead className="hidden md:table-cell">Joined</TableHead>
              <TableHead className="text-right">Actions</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody className={isPending ? "opacity-50 pointer-events-none transition-opacity" : ""}>
            {members.map((member) => {
              const isSelf = member.user_id === currentUserId
              return (
                <TableRow key={member.user_id}>
                  <TableCell>
                    <div className="flex flex-col">
                      <span className="font-medium flex items-center gap-2">
                        {member.email}
                        {isSelf && <Badge variant="secondary" className="h-5 text-[10px] px-1.5">You</Badge>}
                      </span>
                      <span className="text-[10px] text-muted-foreground font-mono mt-0.5">{member.user_id}</span>
                    </div>
                  </TableCell>
                  <TableCell>
                    <div className="flex items-center gap-1.5 text-xs">
                      {member.role_name === "owner" ? (
                        <ShieldCheck className="h-3.5 w-3.5 text-primary" />
                      ) : (
                        <MailCheck className="h-3.5 w-3.5 text-muted-foreground" />
                      )}
                      <span className={member.role_name === "owner" ? "font-semibold text-primary" : "text-muted-foreground"}>
                        {member.role_name.charAt(0).toUpperCase() + member.role_name.slice(1)}
                      </span>
                    </div>
                  </TableCell>
                  <TableCell className="hidden md:table-cell text-xs text-muted-foreground">
                    {new Date(member.created_at).toLocaleDateString()}
                  </TableCell>
                  <TableCell className="text-right">
                    <DropdownMenu>
                      <DropdownMenuTrigger asChild>
                        <Button variant="ghost" className="h-8 w-8 p-0" disabled={isSelf}>
                          <span className="sr-only">Open menu</span>
                          <MoreHorizontal className="h-4 w-4" />
                        </Button>
                      </DropdownMenuTrigger>
                      <DropdownMenuContent align="end" className="w-48">
                        <DropdownMenuLabel>Manage member</DropdownMenuLabel>
                        <DropdownMenuSeparator />

                        <DropdownMenuSub>
                          <DropdownMenuSubTrigger>
                            <span>Change role</span>
                          </DropdownMenuSubTrigger>
                          <DropdownMenuSubContent>
                            <DropdownMenuRadioGroup
                              value={member.role_id}
                              onValueChange={(roleId) => handleRoleChange(member.user_id, roleId)}
                            >
                              {roles.map((role) => (
                                <DropdownMenuRadioItem key={role.id} value={role.id}>
                                  <span className="capitalize">{role.name}</span>
                                </DropdownMenuRadioItem>
                              ))}
                            </DropdownMenuRadioGroup>
                          </DropdownMenuSubContent>
                        </DropdownMenuSub>

                        <DropdownMenuSeparator />

                        <DropdownMenuItem
                          onClick={() => handleRemove(member.user_id)}
                          className="text-destructive focus:bg-destructive focus:text-destructive-foreground relative"
                        >
                          <Trash2 className="mr-2 h-4 w-4" />
                          Remove from business
                        </DropdownMenuItem>
                      </DropdownMenuContent>
                    </DropdownMenu>
                  </TableCell>
                </TableRow>
              )
            })}
          </TableBody>
        </Table>
      </div>
    </div>
  )
}
