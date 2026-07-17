self.addEventListener("push", (event) => {
  const data = event.data?.json() ?? {}
  const title = data.title || "LedgerMind Alert"
  const options = {
    body: data.body || "Something needs your attention.",
    icon: "/favicon.ico",
    badge: "/favicon.ico",
    data: data.url ? { url: data.url } : undefined,
  }

  event.waitUntil(self.registration.showNotification(title, options))
})

self.addEventListener("notificationclick", (event) => {
  event.notification.close()
  const url = event.notification.data?.url || "/dashboard/overview"
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
