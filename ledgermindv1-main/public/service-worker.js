self.addEventListener("push", (event) => {
  const data = event.data?.json() ?? {}
  const title = data.title || "LedgerMind Alert"
  const options = {
    body: data.body || "Something needs your attention.",
    icon: "/favicon.ico",
    badge: "/favicon.ico",
    data: data.url ? { url: safeUrl(data.url) } : undefined,
  }

  event.waitUntil(self.registration.showNotification(title, options))
})

// Only ever open same-origin relative paths. Prevents a crafted push payload
// from opening an attacker-controlled URL when the notification is clicked.
function safeUrl(raw) {
  if (typeof raw !== "string" || !raw.startsWith("/") || raw.startsWith("//")) {
    return "/dashboard/overview"
  }
  return raw
}

self.addEventListener("notificationclick", (event) => {
  event.notification.close()
  const url = safeUrl(event.notification.data?.url || "/dashboard/overview")
  event.waitUntil(
    self.clients.matchAll({ type: "window" }).then((clientList) => {
      for (const client of clientList) {
        if (client.url === url && "focus" in client) {
          return client.focus()
        }
      }
      if (self.clients.openWindow) {
        return self.clients.openWindow(url)
      }
    })
  )
})