"use client"

import { Suspense, useState } from "react"
import { useSearchParams } from "next/navigation"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Package, Mail, CheckCircle, Loader2 } from "lucide-react"
import Link from "next/link"
import { createClient } from "@/lib/supabase/browser"

function SignUpSuccessContent() {
  const searchParams = useSearchParams()
  const email = searchParams.get("email") || ""
  const [isResending, setIsResending] = useState(false)
  const [resendMessage, setResendMessage] = useState<string | null>(null)
  const [resendError, setResendError] = useState<string | null>(null)
  const supabase = createClient()

  async function handleResend() {
    if (!email) {
      setResendError("No email address to resend to. Please sign up again.")
      return
    }

    setIsResending(true)
    setResendMessage(null)
    setResendError(null)

    const { error } = await supabase.auth.resend({
      type: "signup",
      email,
    })

    if (error) {
      setResendError(error.message)
    } else {
      setResendMessage("Confirmation email resent. Check your inbox.")
    }

    setIsResending(false)
  }

  return (
    <div className="min-h-screen flex items-center justify-center bg-background p-6">
      <div className="w-full max-w-md">
        <div className="flex items-center justify-center gap-2 mb-8">
          <Package className="h-8 w-8 text-primary" />
          <h1 className="text-2xl font-bold text-foreground">LedgerMind</h1>
        </div>

        <Card>
          <CardHeader className="text-center">
            <div className="flex justify-center mb-4">
              <div className="h-16 w-16 bg-primary/10 rounded-full flex items-center justify-center">
                <CheckCircle className="h-8 w-8 text-primary" />
              </div>
            </div>
            <CardTitle className="text-2xl">Check your email</CardTitle>
            <CardDescription>
              We&apos;ve sent a confirmation link to {email || "your email address"} to complete your registration.
            </CardDescription>
          </CardHeader>
          <CardContent className="text-center space-y-4">
            <div className="p-4 bg-muted/50 rounded-lg">
              <Mail className="h-6 w-6 text-primary mx-auto mb-2" />
              <p className="text-sm text-muted-foreground">
                Click the link in your email to verify your account and start using LedgerMind.
              </p>
            </div>

            <div className="space-y-2">
              <p className="text-sm text-muted-foreground">Didn&apos;t receive the email? Check your spam folder or</p>
              <Button variant="outline" size="sm" onClick={handleResend} disabled={isResending || !email}>
                {isResending ? (
                  <>
                    <Loader2 className="h-4 w-4 mr-2 animate-spin" />
                    Resending...
                  </>
                ) : (
                  "Resend confirmation email"
                )}
              </Button>
              {resendMessage && <p className="text-sm text-primary">{resendMessage}</p>}
              {resendError && <p className="text-sm text-destructive">{resendError}</p>}
            </div>

            <div className="pt-4 border-t border-border">
              <Link href="/auth/login">
                <Button variant="ghost" className="w-full">
                  Back to sign in
                </Button>
              </Link>
            </div>
          </CardContent>
        </Card>
      </div>
    </div>
  )
}

export default function SignUpSuccessPage() {
  return (
    <Suspense
      fallback={
        <div className="min-h-screen flex items-center justify-center bg-background p-6">
          <div className="h-8 w-8 animate-spin rounded-full border-2 border-primary border-t-transparent" />
        </div>
      }
    >
      <SignUpSuccessContent />
    </Suspense>
  )
}
