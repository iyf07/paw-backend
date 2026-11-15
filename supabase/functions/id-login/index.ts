import { createClient } from 'npm:@supabase/supabase-js@2.119.0';

// Public sign-in endpoint: the Auth service still verifies every one-time code.
// Resolving ID -> email happens only here; never return the resolved email.
Deno.serve(async (req: Request) => {
  const url = Deno.env.get('SUPABASE_URL') ?? '';
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  const local = url.startsWith('http://');
  const allowed = new Set(['https://pawtrip.expo.app', ...(local ? ['http://localhost:8081', 'http://127.0.0.1:8081'] : [])]);
  const origin = req.headers.get('origin');
  const headers = {
    'Content-Type': 'application/json', 'Cache-Control': 'no-store', 'Vary': 'Origin',
    'Access-Control-Allow-Origin': origin && allowed.has(origin) ? origin : 'https://pawtrip.expo.app',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-supabase-client-platform, x-supabase-client-platform-version, x-supabase-client-runtime, x-supabase-client-runtime-version',
  };
  const reply = (status: number, body: unknown) => new Response(JSON.stringify(body), { status, headers });
  if (origin && !allowed.has(origin)) return reply(403, { error: 'invalid_origin' });
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers });
  if (req.method !== 'POST') return reply(405, { error: 'method_not_allowed' });
  if (!url || !anonKey || !serviceKey) return reply(503, { error: 'unavailable' });
  try {
    const raw = await req.text();
    if (raw.length > 2048) return reply(400, { error: 'invalid_request' });
    let body: { action?: unknown; identifier?: unknown; token?: unknown; redirectTo?: unknown };
    try { body = JSON.parse(raw); } catch { return reply(400, { error: 'invalid_request' }); }
    if (!body || typeof body !== 'object') return reply(400, { error: 'invalid_request' });
    const identifier = typeof body.identifier === 'string' ? body.identifier.trim().replace(/^@/, '').toLowerCase() : '';
    if (!/^[a-z0-9_]{3,20}$/.test(identifier) || !['send', 'verify'].includes(String(body.action))) return reply(400, { error: 'invalid_request' });
    const token = typeof body.token === 'string' ? body.token.trim() : '';
    if (body.action === 'verify' && !/^\d{6,8}$/.test(token)) return reply(400, { error: 'invalid_code' });
    const redirectTo = typeof body.redirectTo === 'string' ? body.redirectTo : 'https://pawtrip.expo.app';
    if (body.action === 'send' && !allowed.has(redirectTo) && redirectTo !== 'pawtrip://') return reply(400, { error: 'invalid_redirect' });

    const options = { auth: { autoRefreshToken: false, persistSession: false, detectSessionInUrl: false } };
    const admin = createClient(url, serviceKey, options);
    const { data: profile, error: lookupError } = await admin.from('profiles').select('id').eq('handle', identifier).maybeSingle();
    if (lookupError) return reply(503, { error: 'unavailable' });
    let email: string | undefined;
    if (profile) {
      const { data, error } = await admin.auth.admin.getUserById(profile.id);
      if (error) return body.action === 'send' ? reply(200, { accepted: true }) : reply(401, { error: 'invalid_code' });
      email = data.user?.email;
    }
    const auth = createClient(url, anonKey, options).auth;
    if (body.action === 'send') {
      if (email) {
        // Auth's existing email/IP rate limits and OTP expiry apply. Never auto-create an ID account.
        await auth.signInWithOtp({ email, options: { shouldCreateUser: false, emailRedirectTo: redirectTo } });
      }
      // Same response for existing, unknown and temporarily rate-limited IDs.
      return reply(200, { accepted: true });
    }
    if (!email) return reply(401, { error: 'invalid_code' });
    const { data, error } = await auth.verifyOtp({ email, token, type: 'email' });
    if (error || !data.session) return reply(401, { error: 'invalid_code' });
    return reply(200, { session: { access_token: data.session.access_token, refresh_token: data.session.refresh_token } });
  } catch {
    return reply(503, { error: 'unavailable' });
  }
});
