"use server"

import { revalidatePath } from "next/cache"
import { createServiceClient } from "@/lib/supabase/server"
import { getCurrentUserRoleContext } from "@/lib/supabase/data/user-context"

function generateTempPassword() {
  const chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!@#$%^&*"
  let result = ""
  for (let i = 0; i < 12; i++) {
    result += chars.charAt(Math.floor(Math.random() * chars.length))
  }
  return result
}

async function verifyOwner() {
  const context = await getCurrentUserRoleContext()
  if (!context || context.roleName !== "owner") {
    throw new Error("Unauthorized")
  }
  return context
}

export async function inviteUser(formData: { email: string; roleId: string; businessId: string }) {
  const context = await verifyOwner()
  if (context.businessId !== formData.businessId) {
    throw new Error("Unauthorized")
  }

  const serviceClient = createServiceClient()

  // Check role belongs to business
  const { data: role } = await serviceClient
    .from("custom_roles")
    .select("id")
    .eq("id", formData.roleId)
    .eq("business_id", formData.businessId)
    .single()

  if (!role) {
    throw new Error("Invalid role")
  }

  const tempPassword = generateTempPassword()

  const { data: createdUser, error: createError } = await serviceClient.auth.admin.createUser({
    email: formData.email,
    password: tempPassword,
    email_confirm: true,
    user_metadata: { invited_to_business: formData.businessId },
  })

  if (createError) {
    throw new Error(createError.message)
  }

  const userId = createdUser.user?.id
  if (!userId) {
    throw new Error("User creation failed")
  }

  const { error: roleError } = await serviceClient.from("user_business_roles").insert({
    user_id: userId,
    business_id: formData.businessId,
    role_id: formData.roleId,
  })

  if (roleError) {
    // Best-effort cleanup
    await serviceClient.auth.admin.deleteUser(userId)
    throw new Error(roleError.message)
  }

  revalidatePath("/dashboard/users")
  return { success: true, tempPassword, email: formData.email }
}

export async function updateMemberRole(userId: string, roleId: string, businessId: string) {
  const context = await verifyOwner()
  if (context.businessId !== businessId) {
    throw new Error("Unauthorized")
  }

  if (context.userId === userId) {
    throw new Error("You cannot change your own role.")
  }

  const serviceClient = createServiceClient()

  const { data: role } = await serviceClient
    .from("custom_roles")
    .select("id")
    .eq("id", roleId)
    .eq("business_id", businessId)
    .single()

  if (!role) {
    throw new Error("Invalid role")
  }

  const { error } = await serviceClient
    .from("user_business_roles")
    .update({ role_id: roleId })
    .eq("user_id", userId)
    .eq("business_id", businessId)

  if (error) {
    throw new Error(error.message)
  }

  revalidatePath("/dashboard/users")
  return { success: true }
}

export async function removeMember(userId: string, businessId: string) {
  const context = await verifyOwner()
  if (context.businessId !== businessId) {
    throw new Error("Unauthorized")
  }

  if (context.userId === userId) {
    throw new Error("You cannot remove yourself.")
  }

  const serviceClient = createServiceClient()

  const { error } = await serviceClient
    .from("user_business_roles")
    .delete()
    .eq("user_id", userId)
    .eq("business_id", businessId)

  if (error) {
    throw new Error(error.message)
  }

  revalidatePath("/dashboard/users")
  return { success: true }
}

