"use client"

import { useState } from "react"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { inviteUser } from "@/app/dashboard/users/actions"

export function InviteUserForm({
  businessId,
  roles,
  currentUserId,
}: {
  businessId: string
  roles: { id: string; name: string }[]
  currentUserId: string
}) {
  const [email, setEmail] = useState("")
  const [roleId, setRoleId] = useState(roles[0]?.id || "")
  const [result, setResult] = useState<{ success: boolean; message: string; tempPassword?: string } | null>(null)
  const [pending, setPending] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setPending(true)
    setResult(null)
    try {
      const res = await inviteUser({ email, roleId, businessId })
      setResult({
        success: true,
        message: `Invitation created for ${res.email}. Share the temporary password with them.`,
        tempPassword: res.tempPassword,
      })
      setEmail("")
    } catch (err) {
      setResult({ success: false, message: err instanceof Error ? err.message : "Invitation failed" })
    } finally {
      setPending(false)
    }
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>Invite team member</CardTitle>
      </CardHeader>
      <CardContent>
        <form onSubmit={handleSubmit} className="flex flex-col sm:flex-row gap-4 items-end">
          <div className="flex-1 w-full">
            <Label htmlFor="invite-email">Email</Label>
            <Input
              id="invite-email"
              type="email"
              required
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              placeholder="colleague@business.com"
            />
          </div>
          <div className="w-full sm:w-48">
            <Label htmlFor="invite-role">Role</Label>
            <Select value={roleId} onValueChange={setRoleId} required>
              <SelectTrigger id="invite-role">
                <SelectValue placeholder="Select role" />
              </SelectTrigger>
              <SelectContent>
                {roles.map((role) => (
                  <SelectItem key={role.id} value={role.id}>
                    <span className="capitalize">{role.name}</span>
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <Button type="submit" disabled={pending || !roleId} className="w-full sm:w-auto">
            {pending ? "Inviting..." : "Invite"}
          </Button>
        </form>

        {result && (
          <div
            className={`mt-4 rounded-md p-3 text-sm ${
              result.success
                ? "bg-green-500/10 text-green-600 border border-green-200"
                : "bg-destructive/15 text-destructive"
            }`}
          >
            <p>{result.message}</p>
            {result.tempPassword && (
              <p className="mt-1 font-mono text-xs">Temporary password: {result.tempPassword}</p>
            )}
          </div>
        )}
      </CardContent>
    </Card>
  )
}
