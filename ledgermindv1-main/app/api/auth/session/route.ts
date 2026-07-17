import { NextResponse } from "next/server"

export async function POST() {
  return NextResponse.json({ status: "deprecated" }, { status: 410 })
}

export async function DELETE() {
  return NextResponse.json({ status: "deprecated" }, { status: 410 })
}
