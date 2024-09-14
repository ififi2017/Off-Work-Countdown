"use client"

import * as React from "react"
import * as SwitchPrimitives from "@radix-ui/react-switch"

import { cn } from "@/lib/utils"

const Switch = React.forwardRef<
  React.ElementRef<typeof SwitchPrimitives.Root>,
  React.ComponentPropsWithoutRef<typeof SwitchPrimitives.Root>
>(({ className, ...props }, ref) => (
  <SwitchPrimitives.Root
    className={cn(
      "peer inline-flex h-6 w-11 shrink-0 cursor-pointer items-center rounded-full border border-gray-300 shadow-sm transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-black focus-visible:ring-opacity-75 focus-visible:ring-offset-2 focus-visible:ring-offset-white disabled:cursor-not-allowed disabled:opacity-50 data-[state=checked]:bg-black data-[state=unchecked]:bg-white",
      className
    )}
    {...props}
    ref={ref}
  >
    <SwitchPrimitives.Thumb
      className={cn(
        "pointer-events-none block h-5 w-5 rounded-full bg-white shadow transition-transform data-[state=checked]:translate-x-5 data-[state=unchecked]:translate-x-0.5 data-[state=checked]:bg-white data-[state=unchecked]:bg-black"
      )}
    />
  </SwitchPrimitives.Root>
))
Switch.displayName = SwitchPrimitives.Root.displayName

export { Switch }