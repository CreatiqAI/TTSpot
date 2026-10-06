// The language a member chats with TiTi in, from their own recent messages:
// "zh" (Chinese characters), "ms" (Malay words) or "en" (everything else,
// Manglish included). Cheap on purpose: no model call, no library.
// Used by `titi` (stores profiles.settings.titi_lang after each question) and
// `titi-nudge` (writes its line in that language).

export type Lang = "en" | "zh" | "ms";

// Everyday Malay words that English and Manglish rarely use. "lah", "ok",
// "can" and the like are left out on purpose: Manglish is English here.
const MALAY = new Set([
  "yang", "tak", "tidak", "nak", "hendak", "boleh", "saya", "aku", "kami", "kita", "awak", "kat", "ada", "macam",
  "mana", "apa", "lagi", "dengan", "untuk", "ini", "itu", "kereta", "bila", "berapa", "sudah", "dah", "belum",
  "ke", "je", "sahaja", "cari", "dekat", "hari", "minggu", "esok", "malam", "petang", "pagi", "tolong", "terima",
  "kasih", "bagi", "mahu", "cukai", "jalan", "insurans", "harga", "dan", "atau", "tapi", "kalau", "sebab",
  "pergi", "datang", "mula", "habis", "baru", "lama", "murah", "mahal", "bagus", "cantik", "kawan", "tempat",
  "minyak", "tayar", "enjin", "servis", "bengkel", "berkumpul", "perjumpaan", "sekarang", "nanti", "semalam",
]);

const CJK = /[㐀-鿿豈-﫿]/g;
const WORD = /[a-zA-Z]+/g;

/** One message: "zh" when Chinese characters outweigh Latin words, "ms" when
 * at least two Malay words make up a quarter of its words, else "en". Null
 * when there is nothing to judge (an emoji, a number). */
export function langOf(text: string): Lang | null {
  const cjk = (text.match(CJK) ?? []).length;
  const words = (text.match(WORD) ?? []).map((w) => w.toLowerCase());
  if (cjk === 0 && words.length === 0) return null;
  if (cjk >= 2 && cjk >= words.length) return "zh";
  const malay = words.filter((w) => MALAY.has(w)).length;
  if (malay >= 2 && malay * 4 >= words.length) return "ms";
  return "en";
}

/** The member's language from their recent messages (newest last): Chinese or
 * Malay only when MORE than half of the judged messages are, else English. */
export function detectLang(messages: string[]): Lang {
  const votes = { en: 0, zh: 0, ms: 0 };
  let n = 0;
  for (const m of messages.slice(-10)) {
    const l = langOf(m ?? "");
    if (!l) continue;
    votes[l]++;
    n++;
  }
  if (n === 0) return "en";
  if (votes.zh * 2 > n) return "zh";
  if (votes.ms * 2 > n) return "ms";
  return "en";
}
