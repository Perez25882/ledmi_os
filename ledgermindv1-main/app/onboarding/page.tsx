"use client"

import { useState } from "react"
import { useRouter } from "next/navigation"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Store, Sprout } from "lucide-react"

export default function OnboardingPage() {
  const router = useRouter()
  const [businessName, setBusinessName] = useState("")
  const [branchName, setBranchName] = useState("Accra HQ")
  const [loading, setLoading] = useState(false)
  const [message, setMessage] = useState<string | null>(null)

  async function createBusiness(seedDemo: boolean) {
    setLoading(true)
    setMessage(null)

    try {
      const res = await fetch("/api/onboarding/create-business", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ businessName, branchName }),
      })

      if (!res.ok) {
        const body = await res.json()
        throw new Error(body.error || "Failed to create business")
      }

      if (seedDemo) {
        const seedRes = await fetch("/api/onboarding/seed-demo", { method: "POST" })
        if (!seedRes.ok) {
          const body = await seedRes.json()
          throw new Error(body.error || "Failed to seed demo data")
        }
      }

      router.push("/dashboard/overview")
    } catch (err) {
      setMessage(err instanceof Error ? err.message : String(err))
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="min-h-screen flex items-center justify-center bg-muted/20 p-4">
      <div className="max-w-xl w-full">
        <Card>
          <CardHeader>
            <CardTitle className="text-2xl">Welcome to LedgerMind OS</CardTitle>
            <CardDescription>
              Create your business and first branch to get started.
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            {message && (
              <div className="rounded-md bg-destructive/15 p-3 text-sm text-destructive">
                {message}
              </div>
            )}

            <div className="space-y-2">
              <label className="text-sm font-medium">Business Name</label>
              <Input
                value={businessName}
                onChange={(e) => setBusinessName(e.target.value)}
                placeholder="e.g. Accra Retail Ltd"
              />
            </div>

            <div className="space-y-2">
              <label className="text-sm font-medium">First Branch Name</label>
              <Input
                value={branchName}
                onChange={(e) => setBranchName(e.target.value)}
                placeholder="e.g. Accra HQ"
              />
            </div>

            <div className="grid grid-cols-2 gap-4 pt-4">
              <Button
                disabled={loading || !businessName.trim()}
                onClick={() => createBusiness(false)}
                variant="outline"
              >
                <Store className="h-4 w-4 mr-2" />
                Create Business
              </Button>
              <Button
                disabled={loading || !businessName.trim()}
                onClick={() => createBusiness(true)}
              >
                <Sprout className="h-4 w-4 mr-2" />
                Create + Demo Data
              </Button>
            </div>
          </CardContent>
        </Card>
      </div>
    </div>
  )
}
