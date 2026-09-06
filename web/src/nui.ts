const resourceName = window.GetParentResourceName?.() ?? "qbmultichar";

declare global {
  interface Window { GetParentResourceName?: () => string }
}

export async function fetchNui<T = unknown>(callback: string, data: unknown = {}): Promise<T | null> {
  try {
    const response = await fetch(`https://${resourceName}/${callback}`, {
      method: "POST",
      headers: { "Content-Type": "application/json; charset=UTF-8" },
      body: JSON.stringify(data),
    });
    return response.ok ? await response.json() as T : null;
  } catch {
    return null;
  }
}
