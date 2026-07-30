import { requirePageAccess } from "@/lib/supabase/guards"
import { createServerClientForUser } from "@/lib/supabase/server"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table"
import { ScrollText } from "lucide-react"

export interface AuditLogRow {
  id: string
  created_at: string
  action: string
  entity_type: string | null
  entity_id: string | null
  user_id: string | null
  branch_id: string | null
  details: Record<string, unknown> | null
}

export default async function LogsPage() {
  const context = await requirePageAccess("logs")

  const client = await createServerClientForUser()
  const { data, error } = await client
    .from("activity_logs")
    .select("id, created_at, action, entity_type, entity_id, user_id, branch_id, details")
    .eq("business_id", context.businessId)
    .order("created_at", { ascending: false })
    .limit(200)

  if (error) {
    throw new Error(error.message)
  }

  const logs = (data ?? []) as unknown as AuditLogRow[]

  return (
    <div className="space-y-6 max-w-6xl mx-auto">
      <div>
        <h1 className="text-2xl sm:text-3xl font-bold tracking-tight text-foreground flex items-center gap-2">
          <ScrollText className="h-7 w-7 text-primary" />
          Audit Logs
        </h1>
        <p className="text-muted-foreground text-sm sm:text-base">
          Activity trail for compliance and traceability
        </p>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Recent Activity</CardTitle>
          <CardDescription>Showing the latest 200 events</CardDescription>
        </CardHeader>
        <CardContent>
          <div className="overflow-x-auto -mx-4 sm:mx-0">
            <div className="min-w-[700px] sm:min-w-0">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Timestamp</TableHead>
                    <TableHead>Action</TableHead>
                    <TableHead>Entity</TableHead>
                    <TableHead>Branch</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {logs.length > 0 ? (
                    logs.map((log) => (
                      <TableRow key={log.id}>
                        <TableCell className="font-mono text-xs">
                          {new Date(log.created_at).toLocaleString()}
                        </TableCell>
                        <TableCell>
                          <Badge variant="secondary">{log.action}</Badge>
                        </TableCell>
                        <TableCell className="text-sm">
                          {log.entity_type ? `${log.entity_type}` : "—"}
                        </TableCell>
                        <TableCell className="text-sm text-muted-foreground">
                          {log.branch_id ? log.branch_id.slice(0, 8) : "—"}
                        </TableCell>
                      </TableRow>
                    ))
                  ) : (
                    <TableRow>
                      <TableCell colSpan={4} className="text-center py-8 text-muted-foreground">
                        No activity logged yet.
                      </TableCell>
                    </TableRow>
                  )}
                </TableBody>
              </Table>
            </div>
          </div>
        </CardContent>
      </Card>
    </div>
  )
}
