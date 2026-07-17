"use client"

import { useState, useEffect } from "react"
import { Button } from "@/components/ui/button"
import { Bell } from "lucide-react"
import { toast } from "sonner"

export function PushNotificationsButton() {
  const [isSupported, setIsSupported] = useState(false)
  const [subscribed, setSubscribed] = useState(false)
  const [loading, setLoading] = useState(false)

  useEffect(() => {
    if ("serviceWorker" in navigator && "PushManager" in window) {
      setIsSupported(true)
      navigator.serviceWorker.ready.then((registration) => {
        registration.pushManager.getSubscription().then((sub) => {
          setSubscribed(!!sub)
        })
      })
    }
  }, [])

  async function subscribe() {
    if (!process.env.NEXT_PUBLIC_VAPID_PUBLIC_KEY) {
      toast.error("Push notifications are not configured")
      return
    }

    setLoading(true)
    try {
      const registration = await navigator.serviceWorker.register("/service-worker.js")
      const subscription = await registration.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: urlBase64ToUint8Array(process.env.NEXT_PUBLIC_VAPID_PUBLIC_KEY),
      })

      const json = subscription.toJSON()
      await fetch("/api/push/subscribe", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          endpoint: json.endpoint,
          p256dh: json.keys?.p256dh,
          auth: json.keys?.auth,
        }),
      })

      setSubscribed(true)
      toast.success("Notifications enabled")
    } catch (error) {
      toast.error(error instanceof Error ? error.message : "Failed to enable notifications")
    } finally {
      setLoading(false)
    }
  }

  if (!isSupported) return null

  return (
    <Button variant="outline" size="sm" disabled={loading || subscribed} onClick={subscribe}>
      <Bell className="h-4 w-4 mr-2" />
      {subscribed ? "Notifications On" : loading ? "Enabling..." : "Enable Alerts"}
    </Button>
  )
}

function urlBase64ToUint8Array(base64String: string) {
  const padding = "=".repeat((4 - (base64String.length % 4)) % 4)
  const base64 = (base64String + padding).replace(/\-/g, "+").replace(/_/g, "/")
  const rawData = window.atob(base64)
  return Uint8Array.from(rawData.split("").map((char) => char.charCodeAt(0)))
}
