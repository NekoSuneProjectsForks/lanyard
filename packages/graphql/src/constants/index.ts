// Base URL of the Lanyard instance this gateway proxies.
// Point LANYARD_API_URL at your self-hosted server (see the repo root README)
// or leave it unset to use the public instance.
export const API_URL = process.env.LANYARD_API_URL ?? 'https://api.lanyard.rest'
