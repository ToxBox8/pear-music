// Filtros contra correos inventados, spam y texto sin sentido. Sin dependencias de Cloudflare (salvo `fetch`
// para el DNS), para poder probarlos con `node --test`. Los mensajes se enseñan tal cual en la app.

/** Dominios de correo de usar y tirar o reservados para pruebas. */
export const DISPOSABLE = new Set([
  // Reservados (RFC 2606) y de pruebas
  "example.com", "example.org", "example.net", "example.es", "test.com", "test.es", "prueba.com", "correo.com",
  "email.test", "mail.test", "localhost", "invalid", "asdf.com", "qwerty.com", "abc.com", "aaa.com", "xxx.com",
  "noemail.com", "nomail.com", "fake.com", "fakemail.com", "none.com",
  // Desechables más usados
  "mailinator.com", "mailinator.net", "guerrillamail.com", "guerrillamail.net", "guerrillamail.org",
  "guerrillamailblock.com", "sharklasers.com", "grr.la", "pokemail.net", "spam4.me", "10minutemail.com",
  "10minutemail.net", "10minemail.com", "20minutemail.com", "tempmail.com", "temp-mail.org", "temp-mail.io",
  "tempmail.net", "tempmailo.com", "tempr.email", "tempmail.plus", "tmpmail.org", "tmpmail.net", "tmails.net",
  "yopmail.com", "yopmail.net", "yopmail.fr", "cool.fr.nf", "jetable.fr.nf", "trashmail.com", "trashmail.net",
  "trashmail.de", "trash-mail.com", "throwawaymail.com", "dispostable.com", "maildrop.cc", "mailnesia.com",
  "mailcatch.com", "mintemail.com", "mohmal.com", "getnada.com", "nada.email", "emailondeck.com", "fakeinbox.com",
  "fakemailgenerator.com", "dropmail.me", "moakt.com", "mytemp.email", "burnermail.io", "inboxkitten.com",
  "spamgourmet.com", "mailpoof.com", "emailfake.com", "1secmail.com", "1secmail.net", "1secmail.org",
  "linshiyouxiang.net", "byom.de", "discard.email", "discardmail.com", "spambox.us", "mvrht.com", "getairmail.com",
  "harakirimail.com", "mail.tm", "mailto.plus", "fexpost.com", "fexbox.org", "rover.info", "chacuo.net",
  "anonbox.net", "33mail.com", "spam.la", "tempinbox.com", "mailforspam.com", "incognitomail.org", "deadaddress.com",
  "einrot.com", "kasmail.com", "mailexpire.com", "mail-temp.com", "trbvm.com", "vomoto.com", "wegwerfmail.de",
  "wegwerfmail.net", "zetmail.com", "emltmp.com", "tempmailaddress.com", "luxusmail.org", "cyclelove.cc",
]);

const EMAIL = /^[a-z0-9](?:[a-z0-9._%+-]{0,62}[a-z0-9])?@(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,24}$/i;

/** Primer filtro, sin red: formato estricto, dominios de prueba o desechables y usuarios de relleno. */
export function emailProblem(raw) {
  const email = String(raw ?? "").trim().toLowerCase();
  if (email.length > 254 || !EMAIL.test(email) || email.includes("..")) return "El correo no es válido.";
  const [user, domain] = email.split("@");
  const base = domain.split(".").slice(-2).join(".");
  if (DISPOSABLE.has(domain) || DISPOSABLE.has(base)) {
    return "Usa un correo de verdad: los de usar y tirar o de pruebas no sirven para contestarte.";
  }
  if (/^(test|prueba|asdf+|qwerty|aaa+|xxx+|abc|fake|noreply|no-reply|nobody|none|null|user|usuario)\d*$/.test(user)) {
    return "Ese correo parece inventado. Escribe uno en el que podamos contestarte.";
  }
  return null;
}

/**
 * Segundo filtro, con DNS: el dominio tiene que poder recibir correo (registro MX, o al menos A).
 * Pregunta a 1.1.1.1 por DNS sobre HTTPS. Si el DNS no responde, deja pasar (mejor un reporte de más que
 * perder uno bueno).
 */
export async function domainReceivesMail(domain, fetchFn = fetch) {
  const ask = async (type) => {
    const r = await fetchFn(`https://cloudflare-dns.com/dns-query?name=${encodeURIComponent(domain)}&type=${type}`, {
      headers: { accept: "application/dns-json" },
    });
    if (!r.ok) throw new Error(`DNS ${r.status}`);
    const j = await r.json();
    if (j.Status === 3) return false; // NXDOMAIN: el dominio no existe
    return (j.Answer ?? []).length > 0;
  };
  try {
    if (await ask("MX")) return true;
    return await ask("A");
  } catch {
    return true;
  }
}

const VOWELS = /[aeiouáéíóúüàèìòùâêîôûäëïöy]/i;

/**
 * ¿Es texto sin sentido? Busca lo típico de aporrear el teclado o rellenar: letras repetidas, palabras sin
 * vocales, rachas de consonantes, pocas palabras distintas o casi todo símbolos.
 * Devuelve null si parece un texto normal, o el motivo.
 */
export function textProblem(raw) {
  const text = String(raw ?? "").trim();
  const urls = text.match(/https?:\/\/|www\./gi) ?? [];
  if (urls.length > 2) return "Demasiados enlaces. Cuenta qué ha pasado con tus palabras.";
  const noUrls = text.replace(/\S*(https?:\/\/|www\.)\S*/gi, " ");
  const letters = (noUrls.match(/\p{L}/gu) ?? []).length;
  const visible = noUrls.replace(/\s/g, "").length;
  if (visible === 0 || letters / visible < 0.5) return "El texto no se entiende. Cuenta qué ha pasado con palabras.";
  if (/(.)\1{5,}/u.test(noUrls)) return "El texto no se entiende (hay letras repetidas). Cuenta qué ha pasado.";

  const words = noUrls.toLowerCase().match(/\p{L}+/gu) ?? [];
  const real = words.filter((w) => w.length >= 2);
  if (real.length < 3) return "Cuenta un poco más qué ha pasado (al menos una frase).";
  const distinct = new Set(real);
  if (distinct.size < Math.min(3, real.length) || (real.length >= 6 && distinct.size / real.length < 0.3)) {
    return "El texto se repite mucho. Cuenta qué ha pasado.";
  }
  // Palabras que no parecen palabras: largas y sin vocales, o con 5 consonantes seguidas.
  const odd = real.filter((w) => (w.length >= 4 && !VOWELS.test(w)) || /[^aeiouáéíóúüy\s]{5,}/i.test(w));
  if (odd.length / real.length > 0.34) return "El texto no se entiende. Cuenta qué ha pasado con palabras.";
  // Proporción de vocales imposible en castellano o inglés (aporrear «asdfghjkl» da muy pocas).
  const vowels = (noUrls.match(/[aeiouáéíóúü]/gi) ?? []).length;
  if (letters >= 20 && (vowels / letters < 0.2 || vowels / letters > 0.75)) {
    return "El texto no se entiende. Cuenta qué ha pasado con palabras.";
  }
  return null;
}

/** Resumen SHA-256 corto: los contadores no guardan ni la IP, ni el correo, ni el id del móvil. */
export async function hashId(value) {
  const bytes = new TextEncoder().encode(String(value).trim().toLowerCase());
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest).slice(0, 12)].map((b) => b.toString(16).padStart(2, "0")).join("");
}
