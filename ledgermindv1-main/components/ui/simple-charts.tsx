"use client"

import React from "react"
import { cn } from "@/lib/utils"

interface SimpleBarData {
  month: string
  sales: number
  profit: number
}

interface SimplePieData {
  name: string
  value: number
  color: string
}

interface SimpleBarChartProps {
  data: SimpleBarData[]
  className?: string
}

interface SimplePieChartProps {
  data: SimplePieData[]
  className?: string
}

export function SimpleBarChart({ data, className }: SimpleBarChartProps) {
  if (!data || data.length === 0) {
    return (
      <div className={cn("flex items-center justify-center h-full text-muted-foreground", className)}>
        <div className="text-center">
          <div className="text-sm">No data available</div>
        </div>
      </div>
    )
  }

  const maxValue = Math.max(...data.flatMap(d => [d.sales, d.profit]))
  const chartHeight = 200

  return (
    <div className={cn("w-full p-4", className)}>
      <div className="relative h-full max-w-full overflow-hidden">
        {/* Y-axis labels */}
        <div className="absolute left-0 top-0 h-[200px] flex flex-col justify-between text-xs text-muted-foreground z-10">
          <span>${(maxValue).toLocaleString()}</span>
          <span>${(maxValue * 0.75).toLocaleString()}</span>
          <span>${(maxValue * 0.5).toLocaleString()}</span>
          <span>${(maxValue * 0.25).toLocaleString()}</span>
          <span>$0</span>
        </div>
        
        {/* Chart area */}
        <div className="ml-12 h-[200px] flex items-end justify-between gap-1 min-w-0 pb-8">
          {data.slice(0, 12).map((item, index) => {
            const salesHeight = maxValue > 0 ? (item.sales / maxValue) * chartHeight : 0
            const profitHeight = maxValue > 0 ? (item.profit / maxValue) * chartHeight : 0
            
            return (
              <div key={index} className="flex-1 min-w-[40px] flex flex-col items-center gap-1">
                <div className="flex gap-1 items-end h-[200px] w-full justify-center">
                  <div 
                    className="bg-blue-500 min-w-[8px] w-3 max-w-[16px] rounded-t-sm transition-all hover:bg-blue-600"
                    style={{ height: `${salesHeight}px` }}
                    title={`Sales: $${item.sales.toLocaleString()}`}
                  />
                  <div 
                    className="bg-green-500 min-w-[8px] w-3 max-w-[16px] rounded-t-sm transition-all hover:bg-green-600"
                    style={{ height: `${profitHeight}px` }}
                    title={`Profit: $${item.profit.toLocaleString()}`}
                  />
                </div>
                <span className="text-xs text-muted-foreground text-center truncate w-full" title={item.month}>
                  {item.month}
                </span>
              </div>
            )
          })}
        </div>
        
        {/* Legend */}
        <div className="mt-4 flex justify-center gap-6">
          <div className="flex items-center gap-2">
            <div className="w-3 h-3 bg-blue-500 rounded-sm" />
            <span className="text-xs">Sales</span>
          </div>
          <div className="flex items-center gap-2">
            <div className="w-3 h-3 bg-green-500 rounded-sm" />
            <span className="text-xs">Profit</span>
          </div>
        </div>
      </div>
    </div>
  )
}

export function SimplePieChart({ data, className }: SimplePieChartProps) {
  if (!data || data.length === 0) {
    return (
      <div className={cn("flex items-center justify-center h-full text-muted-foreground", className)}>
        <div className="text-center">
          <div className="text-sm">No data available</div>
        </div>
      </div>
    )
  }

  const total = data.reduce((sum, item) => sum + item.value, 0)
  let currentAngle = 0

  return (
    <div className={cn("w-full h-full flex items-center justify-center p-4", className)}>
      <div className="relative w-full max-w-[280px] h-full max-h-[280px] flex flex-col items-center">
        {/* SVG Chart */}
        <div className="relative w-48 h-48 flex-shrink-0">
          <svg width="192" height="192" viewBox="0 0 192 192" className="transform -rotate-90 w-full h-full">
            {data.map((item, index) => {
              const percentage = item.value / total
              const angle = percentage * 360
              const startAngle = currentAngle
              const endAngle = currentAngle + angle
              
              // Calculate path for pie slice
              const centerX = 96
              const centerY = 96
              const radius = 80
              
              const startAngleRad = (startAngle * Math.PI) / 180
              const endAngleRad = (endAngle * Math.PI) / 180
              
              const x1 = centerX + radius * Math.cos(startAngleRad)
              const y1 = centerY + radius * Math.sin(startAngleRad)
              const x2 = centerX + radius * Math.cos(endAngleRad)
              const y2 = centerY + radius * Math.sin(endAngleRad)
              
              const largeArcFlag = angle > 180 ? 1 : 0
              
              const pathData = [
                `M ${centerX} ${centerY}`,
                `L ${x1} ${y1}`,
                `A ${radius} ${radius} 0 ${largeArcFlag} 1 ${x2} ${y2}`,
                'Z'
              ].join(' ')
              
              currentAngle += angle
              
              return (
                <path
                  key={index}
                  d={pathData}
                  fill={item.color}
                  stroke="white"
                  strokeWidth="2"
                  className="transition-all hover:opacity-80"
                />
              )
            })}
          </svg>
        </div>
        
        {/* Legend */}
        <div className="mt-4 w-full max-w-[240px]">
          <div className="grid grid-cols-1 gap-1 text-center">
            {data.map((item, index) => {
              const percentage = ((item.value / total) * 100).toFixed(0)
              return (
                <div key={index} className="flex items-center justify-center gap-2 text-xs">
                  <div 
                    className="w-3 h-3 rounded-sm flex-shrink-0" 
                    style={{ backgroundColor: item.color }}
                  />
                  <span className="truncate flex-1 text-left">{item.name}</span>
                  <span className="font-medium">{percentage}%</span>
                </div>
              )
            })}
          </div>
        </div>
      </div>
    </div>
  )
}