import { createClient } from 'npm:@supabase/supabase-js@2.119.0';

// Day suggestions for a trip, written by Gemini. The browser sends only {tripId, date, lang}; everything the model sees is
// read here with the caller's own permissions (RLS), so nobody can ask about a trip they are not in. No names, addresses or
// contact details are sent to the model: only the place, dates, the day's plan, weather, interests and dog traits.
const CATS = ['outdoors', 'food', 'coffee', 'sights', 'shopping', 'fun', 'drinks', 'stay', 'transit'];
const MODEL = Deno.env.get('GEMINI_MODEL') ?? 'gemini-flash-lite-latest';
const FRESH_MS = 6 * 3600_000; // a cached answer is reused for this long unless the caller forces a refresh
const DAILY_GENERATIONS_PER_USER = 40;

Deno.serve(async (req: Request) => {
  const url = Deno.env.get('SUPABASE_URL') ?? '';
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  const geminiKey = Deno.env.get('GEMINI_API_KEY') ?? '';
  const local = url.startsWith('http://');
  const allowed = new Set(['https://pawtrip.expo.app', ...(local ? ['http://localhost:8081', 'http://localhost:8082', 'http://127.0.0.1:8081'] : [])]);
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
  if (!geminiKey) return reply(503, { error: 'not_configured' });
  const auth = req.headers.get('authorization') ?? '';
  if (!auth) return reply(401, { error: 'unauthorized' });

  try {
    const raw = await req.text();
    if (raw.length > 1024) return reply(400, { error: 'invalid_request' });
    let body: { tripId?: unknown; date?: unknown; lang?: unknown; force?: unknown };
    try { body = JSON.parse(raw); } catch { return reply(400, { error: 'invalid_request' }); }
    const tripId = typeof body.tripId === 'string' ? body.tripId : '';
    const date = typeof body.date === 'string' ? body.date : '';
    const lang = body.lang === 'en' ? 'en' : 'zh';
    if (!/^[0-9a-f-]{36}$/.test(tripId) || !/^\d{4}-\d{2}-\d{2}$/.test(date)) return reply(400, { error: 'invalid_request' });

    const opts = { auth: { autoRefreshToken: false, persistSession: false, detectSessionInUrl: false } };
    const user = createClient(url, anonKey, { ...opts, global: { headers: { Authorization: auth } } });
    const admin = createClient(url, serviceKey, opts);
    const { data: who } = await user.auth.getUser();
    if (!who.user) return reply(401, { error: 'unauthorized' });

    // the caller must be able to see the trip (RLS)
    const { data: trip } = await user.from('trips').select('id, name, place, lat, lon, tz, start_date, end_date').eq('id', tripId).maybeSingle();
    if (!trip || date < trip.start_date || date > trip.end_date) return reply(403, { error: 'forbidden' });

    const { data: cached } = await user.from('trip_recommendations').select('payload, created_at').eq('trip_id', tripId).eq('day', date).eq('lang', lang).maybeSingle();
    if (cached && body.force !== true && Date.now() - new Date(cached.created_at).getTime() < FRESH_MS) return reply(200, { ...cached.payload, cached: true });

    // a simple guard against runaway use: generations per person per day
    const { count } = await admin.from('trip_recommendations').select('trip_id', { count: 'exact', head: true }).eq('requested_by', who.user.id).gte('created_at', new Date(Date.now() - 86_400_000).toISOString());
    if ((count ?? 0) >= DAILY_GENERATIONS_PER_USER) return reply(429, { error: 'rate_limited' });

    // context, all read with the caller's permissions
    const [{ data: items }, { data: members }, { data: tdogs }] = await Promise.all([
      user.from('items').select('title, cat, date, start_min, confirmed, deleted_at').eq('trip_id', tripId).eq('date', date),
      user.from('trip_members').select('profiles(interests)').eq('trip_id', tripId),
      user.from('trip_dogs').select('dogs(weight_lb, energy, temp, with_dogs, with_people, alone, car, recall)').eq('trip_id', tripId),
    ]);
    const interests = [...new Set((members ?? []).flatMap((m: { profiles: { interests?: string[] } | null }) => m.profiles?.interests ?? []))].slice(0, 12);
    const dogs = (tdogs ?? []).map((d: { dogs: Record<string, unknown> | null }) => d.dogs).filter(Boolean).slice(0, 6);
    const plan = (items ?? []).filter((i: { deleted_at: string | null }) => !i.deleted_at).map((i: { title: string; cat: string; start_min: number | null; confirmed: boolean }) => ({ time: i.start_min == null ? null : `${String(Math.floor(i.start_min / 60)).padStart(2, '0')}:${String(i.start_min % 60).padStart(2, '0')}`, title: String(i.title).slice(0, 60), cat: i.cat, planned: i.confirmed })).slice(0, 12);

    let weather: unknown = null;
    if (trip.lat != null && trip.lon != null) {
      try {
        const w = await fetch(`https://api.open-meteo.com/v1/forecast?latitude=${trip.lat}&longitude=${trip.lon}&daily=temperature_2m_max,temperature_2m_min,precipitation_probability_max&temperature_unit=fahrenheit&timezone=${encodeURIComponent(trip.tz)}&start_date=${date}&end_date=${date}`, { signal: AbortSignal.timeout(4000) });
        if (w.ok) { const j = await w.json(); weather = { hi_f: j.daily?.temperature_2m_max?.[0] ?? null, lo_f: j.daily?.temperature_2m_min?.[0] ?? null, rain_pct: j.daily?.precipitation_probability_max?.[0] ?? null }; }
      } catch { /* weather is optional */ }
    }

    const context = { trip_place: String(trip.place).slice(0, 80), date, weather, group_interests: interests, dogs, plan_for_the_day: plan };
    const system = `You suggest things to do on one day of a dog-friendly group trip. Reply with JSON only. Give 3 or 4 ideas that fit the place, the weather, the group's interests and the dogs (energy, heat/cold tolerance, comfort with other dogs and people, leash recall: 1 is low and 5 is high). Prefer dog-friendly options and say why in one short sentence. Do not repeat what is already planned. Do not invent exact street addresses, opening hours or phone numbers; if you name a real, well-known place be sure it exists, otherwise describe the kind of place. Write in ${lang === 'zh' ? 'Simplified Chinese' : 'English'}. "cat" must be one of: ${CATS.join(', ')}. "when" is a short time of day like "morning", "afternoon", "evening" (in the reply language).`;
    const res = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'x-goog-api-key': geminiKey },
      body: JSON.stringify({
        systemInstruction: { parts: [{ text: system }] },
        contents: [{ role: 'user', parts: [{ text: JSON.stringify(context) }] }],
        generationConfig: {
          temperature: 0.7,
          maxOutputTokens: 700,
          responseMimeType: 'application/json',
          responseSchema: {
            type: 'OBJECT',
            properties: { items: { type: 'ARRAY', items: { type: 'OBJECT', properties: { title: { type: 'STRING' }, why: { type: 'STRING' }, cat: { type: 'STRING', enum: CATS }, when: { type: 'STRING' } }, required: ['title', 'why', 'cat'] } } },
            required: ['items'],
          },
        },
      }),
      signal: AbortSignal.timeout(25_000),
    });
    if (!res.ok) return reply(res.status === 429 ? 429 : 502, { error: res.status === 429 ? 'model_rate_limited' : 'model_error' });
    const out = await res.json();
    const text = out?.candidates?.[0]?.content?.parts?.[0]?.text ?? '';
    let parsed: { items?: { title?: unknown; why?: unknown; cat?: unknown; when?: unknown }[] };
    try { parsed = JSON.parse(text); } catch { return reply(502, { error: 'bad_model_output' }); }
    const list = (parsed.items ?? []).filter((i) => typeof i?.title === 'string' && typeof i?.why === 'string').slice(0, 4).map((i) => ({
      title: String(i.title).slice(0, 80), why: String(i.why).slice(0, 180), cat: CATS.includes(String(i.cat)) ? String(i.cat) : 'sights', when: typeof i.when === 'string' ? i.when.slice(0, 24) : null,
    }));
    if (list.length === 0) return reply(502, { error: 'bad_model_output' });
    const payload = { items: list, model: MODEL };
    await admin.from('trip_recommendations').upsert({ trip_id: tripId, day: date, lang, payload, requested_by: who.user.id, created_at: new Date().toISOString() });
    return reply(200, { ...payload, cached: false });
  } catch {
    return reply(503, { error: 'unavailable' });
  }
});
