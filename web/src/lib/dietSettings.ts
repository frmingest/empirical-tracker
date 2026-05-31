import { getSettings, updateSettings, type UserSettings } from "./api";

/**
 * Loads/saves the diet-focus preference.
 *
 * Signed in → the user_settings table is the source of truth (synced across
 * devices). Not signed in (the mock/demo dashboard) → localStorage, so the
 * toggle still works for exploration. localStorage also acts as a fast cache
 * to avoid a flash of "All" before the API responds.
 */

const LS_KEY = "diet-settings";

export const DEFAULT_SETTINGS: UserSettings = { diet: "all", custom_markers: [] };

function readLocal(): UserSettings {
  if (typeof window === "undefined") return DEFAULT_SETTINGS;
  try {
    const raw = window.localStorage.getItem(LS_KEY);
    if (raw) return JSON.parse(raw) as UserSettings;
  } catch {
    // ignore malformed / unavailable storage
  }
  return DEFAULT_SETTINGS;
}

function writeLocal(settings: UserSettings): void {
  if (typeof window === "undefined") return;
  try {
    window.localStorage.setItem(LS_KEY, JSON.stringify(settings));
  } catch {
    // ignore quota / unavailable storage
  }
}

export async function loadSettings(token: string | null): Promise<UserSettings> {
  if (!token) return readLocal();
  try {
    const settings = await getSettings(token);
    writeLocal(settings);
    return settings;
  } catch {
    return readLocal(); // fall back to cache on network error
  }
}

export async function persistSettings(
  token: string | null,
  settings: UserSettings
): Promise<void> {
  writeLocal(settings); // optimistic local cache
  if (token) {
    try {
      await updateSettings(token, settings);
    } catch {
      // keep the local copy; surface nothing — non-critical preference
    }
  }
}
