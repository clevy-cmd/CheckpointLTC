import { limits } from "./config";
import { ApiError } from "./http";

interface RobloxUser {
  id: number;
  name: string;
  displayName: string;
  description: string;
}

export async function getRobloxUser(userId: number): Promise<RobloxUser | null> {
  let response: Response | null = null;
  for (let attempt = 0; attempt < 3; attempt++) {
    try {
      response = await fetch(`https://users.roblox.com/v1/users/${userId}`, {
        headers: { accept: "application/json", "user-agent": "CheckpointLTC/1" },
        signal: AbortSignal.timeout(limits.robloxLookupTimeoutMs),
      });
      if (response.ok || response.status === 404 || response.status === 400) break;
    } catch {
      response = null;
    }
    await new Promise((resolve) => setTimeout(resolve, 400 * (attempt + 1)));
  }
  if (!response) throw new ApiError("unavailable", "Roblox could not be reached. Try again in a moment.");
  if (response.status === 404 || response.status === 400) return null;
  if (!response.ok) throw new ApiError("unavailable", "Roblox could not be reached. Try again in a moment.");
  const data = (await response.json()) as Partial<RobloxUser>;
  if (typeof data.id !== "number") return null;
  return {
    id: data.id,
    name: String(data.name ?? ""),
    displayName: String(data.displayName ?? ""),
    description: String(data.description ?? ""),
  };
}
