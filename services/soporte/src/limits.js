// Reglas del reporte, sin dependencias de Cloudflare, para poder probarlas con `node --test`.
// Las apps usan los mismos límites (SupportLimits en iOS y Android).

export const LIMITS = {
  maxPhotos: 4,
  maxPhotoBytes: 1_500_000, // cada foto, ya comprimida por la app
  maxTotalBytes: 6_500_000, // por debajo de los 8–10 MB que admite un mensaje de Discord sin mejoras
  minText: 10,
  maxText: 4000,
  // Un reporte por hora por móvil y por correo (lo pidió Toxbox); por IP algo más, porque una casa o una
  // universidad comparten IP.
  perDevicePerHour: 1,
  perEmailPerHour: 1,
  perIpPerHour: 3,
  // El mismo texto desde el mismo móvil se rechaza durante un día.
  repeatWindowSeconds: 86_400,
  // Denegaciones: se guardan 30 días (sin el texto) y se puede apelar una vez cada una, 3 al día por móvil.
  denialTtlSeconds: 30 * 86_400,
  appealsPerDevicePerDay: 3,
  minAppealText: 20,
  maxAppealText: 1500,
};

import { abuseProblem, emailProblem, textProblem } from "./spam.js";

export function validEmail(email) {
  return emailProblem(email) === null;
}

/** ¿Empieza como un JPEG (FF D8 FF)? No basta con el tipo que dice el cliente. */
export function isJpeg(bytes) {
  return bytes.length > 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff;
}

/**
 * Comprueba un reporte ya leído: { email, text, platform, appVersion, os, model, deviceId, photos: [Uint8Array] }.
 * Devuelve null si vale, o el motivo del rechazo (se le enseña al usuario).
 */
export function checkReport(r) {
  const badEmail = emailProblem(r.email);
  if (badEmail) return badEmail;
  const text = (r.text ?? "").trim();
  if (text.length < LIMITS.minText) return "Cuenta un poco más qué ha pasado.";
  if (text.length > LIMITS.maxText) return `El texto es demasiado largo (máximo ${LIMITS.maxText} caracteres).`;
  const badText = textProblem(text) ?? abuseProblem(text);
  if (badText) return badText;
  if (!["ios", "android"].includes(r.platform)) return "Plataforma desconocida.";
  if (!r.deviceId || r.deviceId.length > 64) return "Falta el identificador del dispositivo.";
  const photos = r.photos ?? [];
  if (photos.length > LIMITS.maxPhotos) return `Como mucho ${LIMITS.maxPhotos} fotos.`;
  let total = 0;
  for (const p of photos) {
    if (p.length > LIMITS.maxPhotoBytes) return "Una de las fotos es demasiado grande.";
    if (!isJpeg(p)) return "Sólo se admiten fotos JPEG.";
    total += p.length;
  }
  if (total > LIMITS.maxTotalBytes) return "Las fotos pesan demasiado en total.";
  return null;
}

/** Clave del contador de la hora en curso (Workers KV caduca las claves solas). */
export function rateKey(kind, id, now = Date.now()) {
  return `rl:${kind}:${id}:${Math.floor(now / 3_600_000)}`;
}

/** El mensaje de Discord (embed) con los datos del reporte. Recorta lo que Discord no admite. */
export function discordPayload(r) {
  const field = (name, value) => ({ name, value: String(value || "—").slice(0, 1024), inline: true });
  return {
    username: "Pear Music · soporte",
    allowed_mentions: { parse: [] },
    embeds: [
      {
        title: `${r.kind === "sugerencia" ? "💡 Sugerencia" : "Reporte"}${r.ticket ? ` #${r.ticket}` : ""} desde ${r.platform === "ios" ? "iOS" : "Android"} ${r.appVersion ?? ""}`.trim(),
        description: r.text.trim().slice(0, 4000),
        color: r.kind === "sugerencia" ? 0x34c759 : 0x8b5cf6,
        fields: [
          field("Correo", r.email.trim()),
          field("Sistema", r.os),
          field("Modelo", r.model),
          field("Dispositivo", r.deviceId.slice(0, 8)),
          ...(r.ticket ? [field("Ticket", `#${r.ticket} · contesta con /msg, abre con /rp ${r.ticket} o`)] : []),
        ],
        timestamp: new Date().toISOString(),
      },
    ],
  };
}
