"use client"

import { useCallback, useRef, useState } from "react"
import Papa from "papaparse"
import { toast } from "sonner"
import Link from "next/link"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Progress } from "@/components/ui/progress"
import { Badge } from "@/components/ui/badge"
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card"
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table"
import { importProductsAction } from "./actions"
import type { ProductImportRow } from "@/lib/supabase/data/product-import"
import { Upload, Download, ArrowLeft, FileSpreadsheet, CheckCircle2 } from "lucide-react"

interface Category {
  id: string
  name: string
}

interface ParsedRow extends ProductImportRow {
  _rowNumber: number
  _errors: string[]
}

const TEMPLATE_COLUMNS = [
  "name",
  "barcode",
  "category",
  "price",
  "cost_price",
  "stock_quantity",
  "unit",
] as const

const TEMPLATE_ROWS = [
  ["Coca-Cola 500ml", "5449000000996", "Drinks", "5.00", "3.50", "48", "bottle"],
  ["Rice 1kg", "", "Groceries", "12.00", "9.00", "20", "pack"],
] as const

function downloadTemplate() {
  const header = TEMPLATE_COLUMNS.join(",")
  const lines = [header, ...TEMPLATE_ROWS.map((r) => r.join(","))]
  const csv = lines.join("\n")
  const blob = new Blob([csv], { type: "text/csv;charset=utf-8;" })
  const url = URL.createObjectURL(blob)
  const a = document.createElement("a")
  a.href = url
  a.download = "product-import-template.csv"
  document.body.appendChild(a)
  a.click()
  document.body.removeChild(a)
  URL.revokeObjectURL(url)
}

function toNumber(value: unknown): number {
  if (value === null || value === undefined || value === "") return NaN
  const n = Number(String(value).replace(/[^0-9.\-]/g, ""))
  return Number.isFinite(n) ? n : NaN
}

function validateRows(raw: Record<string, string>[]): ParsedRow[] {
  return raw.map((r, idx) => {
    const rowNumber = idx + 2 // header is row 1
    const errors: string[] = []

    const name = (r.name ?? "").trim()
    const price = toNumber(r.price)
    const costPrice = r.cost_price !== "" && r.cost_price !== undefined ? toNumber(r.cost_price) : NaN

    if (!name) errors.push("Missing name")
    if (Number.isNaN(price) || price < 0) errors.push("Invalid price")
    if (r.cost_price !== "" && r.cost_price !== undefined && (Number.isNaN(costPrice) || costPrice < 0)) {
      errors.push("Invalid cost_price")
    }

    return {
      _rowNumber: rowNumber,
      _errors: errors,
      name,
      barcode: (r.barcode ?? "").trim() || undefined,
      category: (r.category ?? "").trim() || undefined,
      price,
      cost_price: Number.isNaN(costPrice) ? undefined : costPrice,
      stock_quantity: toNumber(r.stock_quantity),
      unit: (r.unit ?? "").trim() || undefined,
    }
  })
}

export function ImportClient({ categories }: { categories: Category[] }) {
  const inputRef = useRef<HTMLInputElement>(null)
  const [fileName, setFileName] = useState<string | null>(null)
  const [rows, setRows] = useState<ParsedRow[]>([])
  const [parsing, setParsing] = useState(false)
  const [importing, setImporting] = useState(false)
  const [progress, setProgress] = useState(0)
  const [result, setResult] = useState<{
    imported: number
    skipped: number
    errors: string[]
  } | null>(null)
  const [dragOver, setDragOver] = useState(false)

  const validRows = rows.filter((r) => r._errors.length === 0)
  const errorRowCount = rows.length - validRows.length

  const handleFile = useCallback((file: File) => {
    setFileName(file.name)
    setRows([])
    setResult(null)
    setParsing(true)

    Papa.parse<Record<string, string>>(file, {
      header: true,
      skipEmptyLines: true,
      transformHeader: (h) => h.trim().toLowerCase(),
      complete: (res) => {
        const validated = validateRows(res.data)
        setRows(validated)
        setParsing(false)
        if (validated.length === 0) {
          toast.error("No rows found in file")
        } else {
          toast.success(`Parsed ${validated.length} rows`)
        }
      },
      error: (err) => {
        setParsing(false)
        toast.error(err.message || "Failed to parse file")
      },
    })
  }, [])

  const onDrop = useCallback(
    (e: React.DragEvent<HTMLDivElement>) => {
      e.preventDefault()
      setDragOver(false)
      const file = e.dataTransfer.files?.[0]
      if (file) handleFile(file)
    },
    [handleFile]
  )

  async function handleImport() {
    if (validRows.length === 0) {
      toast.error("No valid rows to import")
      return
    }
    setImporting(true)
    setResult(null)
    setProgress(10)

    try {
      // Drive the progress bar while the server action runs.
      const tick = setInterval(() => {
        setProgress((p) => (p < 90 ? p + 5 : p))
      }, 200)

      const payload: ProductImportRow[] = validRows.map((r) => ({
        name: r.name,
        barcode: r.barcode,
        category: r.category,
        price: r.price,
        cost_price: r.cost_price,
        stock_quantity: r.stock_quantity,
        unit: r.unit,
      }))

      const res = await importProductsAction(payload)
      clearInterval(tick)
      setProgress(100)
      setResult(res)
      toast.success(`Imported ${res.imported} products, skipped ${res.skipped} errors`)
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Import failed")
    } finally {
      setImporting(false)
    }
  }

  function reset() {
    setRows([])
    setFileName(null)
    setResult(null)
    setProgress(0)
    if (inputRef.current) inputRef.current.value = ""
  }

  return (
    <div className="space-y-6">
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
        <div>
          <h1 className="text-2xl sm:text-3xl font-bold text-foreground">
            Import Products
          </h1>
          <p className="text-muted-foreground text-sm sm:text-base">
            Bulk-import products from a CSV or XLSX file.
          </p>
        </div>
        <div className="flex gap-2">
          <Button asChild variant="outline">
            <Link href="/dashboard/catalog">
              <ArrowLeft className="h-4 w-4" />
              Back to Catalog
            </Link>
          </Button>
          <Button variant="outline" onClick={downloadTemplate}>
            <Download className="h-4 w-4" />
            Download Template
          </Button>
        </div>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Upload File</CardTitle>
          <CardDescription>
            Accepted formats: .csv, .xlsx. Columns: {TEMPLATE_COLUMNS.join(", ")}
          </CardDescription>
        </CardHeader>
        <CardContent>
          <div
            onDragOver={(e) => {
              e.preventDefault()
              setDragOver(true)
            }}
            onDragLeave={() => setDragOver(false)}
            onDrop={onDrop}
            className={`flex flex-col items-center justify-center gap-3 rounded-lg border-2 border-dashed p-10 text-center transition-colors ${
              dragOver ? "border-primary bg-primary/5" : "border-border"
            }`}
          >
            <FileSpreadsheet className="h-10 w-10 text-muted-foreground" />
            <div>
              <p className="text-sm font-medium">
                Drag & drop a file here, or click to select
              </p>
              <p className="text-xs text-muted-foreground">.csv or .xlsx</p>
            </div>
            <Input
              ref={inputRef}
              type="file"
              accept=".csv,.xlsx,text/csv,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
              className="hidden"
              onChange={(e) => {
                const file = e.target.files?.[0]
                if (file) handleFile(file)
              }}
            />
            <Button
              variant="secondary"
              onClick={() => inputRef.current?.click()}
              disabled={importing}
            >
              <Upload className="h-4 w-4" />
              Select File
            </Button>
            {fileName && (
              <p className="text-xs text-muted-foreground">
                Selected: <span className="font-medium">{fileName}</span>
              </p>
            )}
          </div>

          {categories.length > 0 && (
            <div className="mt-4 flex flex-wrap items-center gap-2">
              <span className="text-xs text-muted-foreground">Valid categories:</span>
              {categories.map((c) => (
                <Badge key={c.id} variant="secondary" className="text-xs">
                  {c.name}
                </Badge>
              ))}
            </div>
          )}
        </CardContent>
      </Card>

      {parsing && (
        <Card>
          <CardContent className="py-6 text-center text-sm text-muted-foreground">
            Parsing file...
          </CardContent>
        </Card>
      )}

      {rows.length > 0 && (
        <Card>
          <CardHeader>
            <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
              <div>
                <CardTitle>Preview</CardTitle>
                <CardDescription>
                  {rows.length} rows parsed ·{" "}
                  <span className="text-green-600 font-medium">
                    {validRows.length} valid
                  </span>{" "}
                  ·{" "}
                  <span className="text-destructive font-medium">
                    {errorRowCount} with errors
                  </span>
                </CardDescription>
              </div>
              <div className="flex gap-2">
                <Button variant="ghost" onClick={reset} disabled={importing}>
                  Clear
                </Button>
                <Button
                  onClick={handleImport}
                  disabled={importing || validRows.length === 0}
                >
                  {importing
                    ? "Importing..."
                    : `Import ${validRows.length} Product${validRows.length === 1 ? "" : "s"}`}
                </Button>
              </div>
            </div>
          </CardHeader>
          <CardContent className="space-y-4">
            {importing && (
              <div className="space-y-2">
                <Progress value={progress} />
                <p className="text-xs text-muted-foreground text-right">
                  {progress}%
                </p>
              </div>
            )}

            <div className="overflow-x-auto -mx-4 sm:mx-0">
              <div className="min-w-[800px] sm:min-w-0">
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead className="w-16">Row</TableHead>
                      <TableHead>Name</TableHead>
                      <TableHead>Barcode</TableHead>
                      <TableHead>Category</TableHead>
                      <TableHead className="text-right">Price</TableHead>
                      <TableHead className="text-right">Cost</TableHead>
                      <TableHead className="text-right">Stock</TableHead>
                      <TableHead>Issues</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {rows.map((row) => (
                      <TableRow
                        key={row._rowNumber}
                        className={row._errors.length > 0 ? "bg-destructive/5" : ""}
                      >
                        <TableCell className="text-muted-foreground">
                          {row._rowNumber}
                        </TableCell>
                        <TableCell className="font-medium">
                          {row.name || (
                            <span className="text-destructive">—</span>
                          )}
                        </TableCell>
                        <TableCell>{row.barcode || "-"}</TableCell>
                        <TableCell>{row.category || "-"}</TableCell>
                        <TableCell className="text-right">
                          {Number.isNaN(row.price) ? (
                            <span className="text-destructive">invalid</span>
                          ) : (
                            row.price.toFixed(2)
                          )}
                        </TableCell>
                        <TableCell className="text-right">
                          {row.cost_price !== undefined ? row.cost_price.toFixed(2) : "-"}
                        </TableCell>
                        <TableCell className="text-right">
                          {Number.isNaN(row.stock_quantity) ? "-" : row.stock_quantity}
                        </TableCell>
                        <TableCell>
                          {row._errors.length > 0 ? (
                            <div className="flex flex-col gap-1">
                              {row._errors.map((err, i) => (
                                <Badge key={i} variant="destructive" className="text-xs w-fit">
                                  {err}
                                </Badge>
                              ))}
                            </div>
                          ) : (
                            <Badge variant="secondary" className="text-xs">
                              OK
                            </Badge>
                          )}
                        </TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              </div>
            </div>
          </CardContent>
        </Card>
      )}

      {result && (
        <Card className="border-green-500/30">
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <CheckCircle2 className="h-5 w-5 text-green-600" />
              Import Complete
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-3">
            <p className="text-sm">
              Imported{" "}
              <span className="font-bold text-green-600">{result.imported}</span>{" "}
              products, skipped{" "}
              <span className="font-bold text-destructive">{result.skipped}</span>{" "}
              errors.
            </p>
            {result.errors.length > 0 && (
              <div className="rounded-md border border-border bg-muted/30 p-3 max-h-48 overflow-auto">
                <p className="text-xs font-medium mb-2 text-muted-foreground">
                  Error details:
                </p>
                <ul className="text-xs space-y-1">
                  {result.errors.map((err, i) => (
                    <li key={i} className="text-muted-foreground">
                      • {err}
                    </li>
                  ))}
                </ul>
              </div>
            )}
            <div className="flex gap-2">
              <Button asChild>
                <Link href="/dashboard/catalog">View Catalog</Link>
              </Button>
              <Button variant="outline" onClick={reset}>
                Import Another File
              </Button>
            </div>
          </CardContent>
        </Card>
      )}
    </div>
  )
}
