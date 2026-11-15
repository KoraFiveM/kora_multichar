import { useCallback, useSyncExternalStore } from "react"

type LocaleTable = Record<string, unknown>
type Listener = () => void

let Locales: LocaleTable = {}
const listeners = new Set<Listener>()

function subscribe(listener: Listener) {
  listeners.add(listener)
  return () => listeners.delete(listener)
}

function snapshot() {
  return Locales
}

export function setLocales(value: unknown) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return
  Locales = value as LocaleTable
  listeners.forEach((listener) => listener())
}

export function useLocales() {
  return useSyncExternalStore(subscribe, snapshot, snapshot)
}

export function useLocale() {
  const locales = useLocales()
  return useCallback((key: string, ...values: Array<string | number>) => {
    let value: unknown = locales
    for (const part of key.split(".")) {
      if (!value || typeof value !== "object") return key
      value = (value as LocaleTable)[part]
    }
    if (typeof value !== "string") return key
    let index = 0
    return value.replace(/%[sd]/g, (token) => {
      const replacement = values[index++]
      return replacement === undefined ? token : String(replacement)
    })
  }, [locales])
}
