export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type UUID = string

// ─── Core tenant & RBAC ───────────────────────────────────────────────────────

export interface Business {
  id: UUID
  name: string
  is_active: boolean
  created_at: string
  updated_at: string
  deleted_at: string | null
}

export interface Branch {
  id: UUID
  business_id: UUID
  name: string
  location: string | null
  phone: string | null
  is_active: boolean
  created_at: string
  updated_at: string
  deleted_at: string | null
}

export interface CustomRole {
  id: UUID
  business_id: UUID
  name: string
  permissions: Record<string, boolean>
  created_at: string
  updated_at: string
}

export interface UserBusinessRole {
  user_id: UUID
  business_id: UUID
  role_id: UUID
  created_at: string
  updated_at: string
}

export interface AppUser {
  id: UUID
  email: string | null
  phone: string | null
  full_name: string | null
  avatar_url: string | null
  created_at: string
  updated_at: string
}

// ─── Catalog ─────────────────────────────────────────────────────────────────

export interface Category {
  id: UUID
  business_id: UUID
  name: string
  created_at: string
  updated_at: string
}

export interface Supplier {
  id: UUID
  business_id: UUID
  name: string
  contact_email: string | null
  contact_phone: string | null
  created_at: string
  updated_at: string
  deleted_at: string | null
}

export interface Product {
  id: UUID
  business_id: UUID
  name: string
  sku: string | null
  barcode: string | null
  selling_price: number
  cost_price: number
  category_id: UUID | null
  supplier_id: UUID | null
  reorder_threshold: number
  created_at: string
  updated_at: string
  deleted_at: string | null
}

// ─── Inventory ───────────────────────────────────────────────────────────────

export interface Inventory {
  product_id: UUID
  business_id: UUID
  quantity: number
  updated_at: string
}

export type InventoryLogReason =
  | "sale"
  | "return"
  | "restock"
  | "adjustment"
  | "transfer"
  | "damage"

export interface InventoryLog {
  id: UUID
  business_id: UUID
  product_id: UUID
  branch_id: UUID | null
  old_quantity: number
  new_quantity: number
  change_amount: number
  reason: InventoryLogReason
  actor_id: UUID | null
  created_at: string
}

// ─── POS carts ───────────────────────────────────────────────────────────────

export type CartStatus = "ACTIVE" | "HOLD" | "ABANDONED" | "COMPLETED"

export interface Cart {
  id: UUID
  business_id: UUID
  branch_id: UUID
  cashier_id: UUID
  status: CartStatus
  created_at: string
  updated_at: string
}

export interface CartItem {
  id: UUID
  cart_id: UUID
  product_id: UUID
  quantity: number
  unit_price: number
  created_at: string
  updated_at: string
}

// ─── Payments (legacy + event-sourced) ───────────────────────────────────────

export type PaymentMethod =
  | "cash"
  | "momo"
  | "card"
  | "bank_transfer"
  | "split"

export type PaymentStatus =
  | "PENDING"
  | "COMPLETED"
  | "FAILED"
  | "REFUNDED"
  | "CANCELLED"

export interface Payment {
  id: UUID
  business_id: UUID
  branch_id: UUID | null
  cashier_id: UUID
  method: PaymentMethod
  amount: number
  status: PaymentStatus
  provider_reference: string | null
  card_last4: string | null
  card_brand: string | null
  created_at: string
}

export type PaymentIntentStatus =
  | "initiated"
  | "pending"
  | "completed"
  | "failed"
  | "refunded"
  | "disputed"

export interface PaymentIntent {
  id: UUID
  business_id: UUID
  branch_id: UUID | null
  cart_id: UUID | null
  invoice_id: UUID | null
  customer_reference: string | null
  amount: number
  currency: string
  idempotency_key: UUID
  provider: string
  provider_reference: string | null
  status: PaymentIntentStatus
  legacy_payment_id: UUID | null
  created_by: UUID
  created_at: string
  updated_at: string
}

export type PaymentEventType =
  | "payment_initiated"
  | "payment_authorized"
  | "payment_captured"
  | "payment_failed"
  | "payment_refunded"
  | "payment_partially_refunded"
  | "chargeback_created"
  | "chargeback_won"
  | "chargeback_lost"
  | "payment_cancelled"
  | "webhook_received"

export interface PaymentEvent {
  id: UUID
  payment_intent_id: UUID
  event_type: PaymentEventType
  provider: string
  provider_event_id: string | null
  provider_reference: string | null
  payload: Json
  occurred_at: string
  received_at: string
  created_at: string
}

export interface WebhookReceipt {
  id: UUID
  provider: string
  provider_event_id: string
  event_type: string
  signature_valid: boolean
  payload_hash: string
  raw_payload: Json
  received_at: string
  created_at: string
}

export interface PaymentProcessingMarker {
  id: UUID
  payment_intent_id: UUID
  event_id: UUID
  processed_at: string
}

// ─── Sales & invoices ────────────────────────────────────────────────────────

export interface Invoice {
  id: UUID
  business_id: UUID
  branch_id: UUID | null
  invoice_number: string
  cashier_id: UUID
  payment_id: UUID
  subtotal: number
  tax: number
  total: number
  created_at: string
  updated_at: string
}

export interface Sale {
  id: UUID
  business_id: UUID
  branch_id: UUID
  invoice_id: UUID
  payment_id: UUID
  cashier_id: UUID
  created_at: string
  updated_at: string
}

export interface SaleItem {
  id: UUID
  sale_id: UUID
  product_id: UUID
  quantity: number
  unit_price: number
  subtotal: number
  created_at: string
  updated_at: string
}

// ─── Activity & AI ───────────────────────────────────────────────────────────

export interface ActivityLog {
  id: UUID
  business_id: UUID
  actor_id: UUID | null
  action: string
  entity_table: string | null
  entity_id: UUID | null
  metadata: Json
  created_at: string
}

export type AIInsightType =
  | "reorder"
  | "anomaly"
  | "margin"
  | "trend"
  | "forecast"
  | "recommendation"

export interface AIInsight {
  id: UUID
  business_id: UUID
  branch_id: UUID | null
  insight_type: AIInsightType
  title: string
  description: string
  data: Json
  confidence_score: number | null
  is_read: boolean
  is_actioned: boolean
  created_at: string
}

// ─── Business context helper used by dashboard layouts ─────────────────────────

export interface BusinessContext {
  user: AppUser
  business: Business
  branch: Branch
  role: CustomRole
}
