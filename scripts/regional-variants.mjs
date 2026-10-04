// British English and Latin American Spanish, derived from `en` and `es`.
//
// Only strings that actually change are stored. iOS then falls back
// en-GB → en and es-MX → es (`NativeLocalizer`); Android resource
// resolution does the same from `values-en-rGB` and `values-b+es+419`.
// The wording is a first pass for a native speaker to review.

const PLACEHOLDER = /\{\{\w+\}\}|%(?:\d+\$)?(?:lld|@|d|s)/g;

/** Regions whose English spelling follows the United States, not Britain. */
export const AMERICAN_ENGLISH_REGIONS = ["US", "CA", "PH", "LR", "PR", "GU", "AS", "VI", "UM", "MP"];

/**
 * Spanish regions whose CLDR parent is `es-419` (Latin America), including
 * `es-US`. Spain (`ES`), Equatorial Guinea and a bare `es` stay on `es`.
 */
export const LATIN_AMERICAN_REGIONS = [
  "419", "MX", "AR", "BO", "BR", "BZ", "CL", "CO", "CR", "CU", "DO", "EC", "GT", "HN",
  "NI", "PA", "PE", "PR", "PY", "SV", "US", "UY", "VE",
];

function protect(text, edit) {
  const tokens = [];
  const shielded = text.replace(PLACEHOLDER, (token) => {
    tokens.push(token);
    return `\u0001${tokens.length - 1}\u0001`;
  });
  return edit(shielded).replace(/\u0001(\d+)\u0001/g, (_, index) => tokens[Number(index)]);
}

function replaceWord(text, from, to) {
  return text.replace(new RegExp(`\\b${from}\\b`, "g"), to);
}

/**
 * Roster noun only. "scheduled" / "unscheduled" and the verb
 * ("schedule the reminder", or a button that is just "Schedule") stay.
 */
function titled(word, replacement) {
  return word[0] === word[0].toUpperCase() && word[0] !== word[0].toLowerCase()
    ? replacement[0].toUpperCase() + replacement.slice(1)
    : replacement;
}

function replaceScheduleNoun(text) {
  if (text === "Schedule" || text === "schedule") return text;
  const schedules = text.replace(/\b(?:schedules|Schedules|schedule|Schedule)\b/g, (word, offset, whole) => {
    const after = whole.slice(offset + word.length);
    if (/^(schedule|Schedule)$/.test(word) && /^\s+(the|a|an)\b/.test(after)) return word;
    return titled(word, word.toLowerCase() === "schedules" ? "rotas" : "rota");
  });
  return schedules.replace(/\b(?:rosters|Rosters|roster|Roster)\b/g, (word) =>
    titled(word, word.toLowerCase().endsWith("s") ? "rotas" : "rota")
  );
}

/** Public-holiday wording. A word already inside "bank holiday" is left alone. */
function replacePublicHoliday(text) {
  const national = text.replace(/\bnational holiday\b/g, "bank holiday").replace(/\bNational holiday\b/g, "Bank holiday");
  return national.replace(/\b[Hh]olidays?\b/g, (word, offset, whole) => {
    const before = whole.slice(Math.max(0, offset - 5), offset);
    if (/bank $/i.test(before)) return word;
    const bank = word[0] === "H" ? "Bank" : "bank";
    return word.toLowerCase().endsWith("s") ? `${bank} holidays` : `${bank} holiday`;
  });
}

/** en → en-GB. Identical input is returned unchanged. */
export function toBritishEnglish(text) {
  return protect(text, (value) => {
    let next = value;
    next = replaceWord(next, "licenses", "licences");
    next = replaceWord(next, "Licenses", "Licences");
    next = replaceWord(next, "dialogs", "dialogues");
    next = replaceWord(next, "Dialogs", "Dialogues");
    next = replaceWord(next, "dialog", "dialogue");
    next = replaceWord(next, "Dialog", "Dialogue");
    next = replaceWord(next, "colors", "colours");
    next = replaceWord(next, "Colors", "Colours");
    next = replaceWord(next, "color", "colour");
    next = replaceWord(next, "Color", "Colour");
    next = replaceWord(next, "customize", "customise");
    next = replaceWord(next, "Customize", "Customise");
    next = replaceWord(next, "customized", "customised");
    next = replaceWord(next, "customizing", "customising");
    next = replaceWord(next, "organize", "organise");
    next = replaceWord(next, "Organize", "Organise");
    next = replaceWord(next, "organized", "organised");
    next = replaceWord(next, "organizing", "organising");
    next = replaceWord(next, "canceled", "cancelled");
    next = replaceWord(next, "Canceled", "Cancelled");
    next = replaceWord(next, "canceling", "cancelling");
    next = replaceWord(next, "Canceling", "Cancelling");
    next = replacePublicHoliday(next);
    next = replaceScheduleNoun(next);
    return next;
  });
}

const SETTINGS_PAIRS = [
  ["todos los ajustes de la app", "toda la configuración de la app"],
  ["los ajustes del sistema", "la configuración del sistema"],
  ["ajustes del sistema", "configuración del sistema"],
  ["Ajustes de Pomodoro", "Configuración de Pomodoro"],
  ["Estos ajustes se aplican", "Esta configuración se aplica"],
  ["estos ajustes", "esta configuración"],
  ["Estos ajustes", "Esta configuración"],
  ["tus ajustes salariales", "tu configuración salarial"],
  ["tus ajustes de vida", "tu configuración de vida"],
  ["tus ajustes", "tu configuración"],
  ["Tus ajustes", "Tu configuración"],
  ["Abrir ajustes de comida", "Abrir configuración de comida"],
  ["Abrir ajustes", "Abrir configuración"],
  ["en Ajustes", "en Configuración"],
  ["de Ajustes", "de Configuración"],
  ["Abrir Ajustes", "Abrir Configuración"],
];

/** Shift-roster "horario" only, and not "horario laboral" / "fuera del horario". */
function replaceRoster(text) {
  let next = text.replaceAll("Horario y turnos", "Horas y rol de turnos");
  next = next.replaceAll("horario de trabajo", "rol de turnos").replaceAll("Horario de trabajo", "Rol de turnos");
  const held = [];
  next = next.replace(/horario laboral|fuera del horario/g, (token) => {
    held.push(token);
    return `\u0002${held.length - 1}\u0002`;
  });
  next = next.replace(/\bHorario\b/g, "Rol de turnos").replace(/\bhorario\b/g, "rol de turnos");
  return next.replace(/\u0002(\d+)\u0002/g, (_, index) => held[Number(index)]);
}

/**
 * es → es-MX (Latin American Spanish, stored as es-MX and shipped on Android
 * as es-419). `english` decides whether "horario" is the shift roster: only
 * when the English noun is schedule/roster. Hours ("Set the hours") stay
 * "horario". Tú / usted stay as in `es`. Vosotros does not occur in `es`.
 * `jornada` stays: it is ordinary Latin American usage for a workday.
 * `móvil`, `ordenador` and `vale` do not occur in `es`.
 */
export function toLatinAmericanSpanish(text, english = "") {
  return protect(text, (value) => {
    let next = value
      .replaceAll("cuenta atrás hasta", "hace la cuenta regresiva hasta")
      .replaceAll("Cuenta atrás hasta", "Hace la cuenta regresiva hasta")
      .replaceAll("Cuenta atrás", "Cuenta regresiva")
      .replaceAll("cuenta atrás", "cuenta regresiva");
    next = next.replaceAll("Festivo", "Feriado").replaceAll("festivo", "feriado");
    if (next === "Ajustes") next = "Configuración";
    for (const [from, to] of SETTINGS_PAIRS) next = next.replaceAll(from, to);
    next = next
      .replaceAll("tu configuración se quedarán", "tu configuración se quedará")
      .replaceAll("tu configuración de vida actuales", "tu configuración de vida actual");
    if (replaceScheduleNoun(english) !== english) next = replaceRoster(next);
    return next;
  });
}

export function regionalVariant(locale, text, english = "") {
  if (locale === "en-GB") return toBritishEnglish(text);
  if (locale === "es-MX") return toLatinAmericanSpanish(text, english);
  return text;
}

function unitsOf(localization) {
  if (!localization) return [];
  if (localization.stringUnit && typeof localization.stringUnit.value === "string") {
    return [{ name: null, value: localization.stringUnit.value }];
  }
  const plural = localization.variations?.plural;
  if (!plural) return [];
  return Object.entries(plural).map(([name, variant]) => ({ name, value: variant.stringUnit.value }));
}

function mapLocalization(localization, edit) {
  if (!localization) return null;
  const source = unitsOf(localization);
  if (source.length === 0) return null;
  let changed = false;
  const edited = source.map((unit) => {
    const value = edit(unit.value);
    if (value !== unit.value) changed = true;
    return { ...unit, value };
  });
  if (!changed) return null;
  if (localization.stringUnit) return { stringUnit: { state: "translated", value: edited[0].value } };
  const plural = {};
  for (const unit of edited) plural[unit.name] = { stringUnit: { state: "translated", value: unit.value } };
  return { variations: { plural } };
}

function spanishLocalization(enLoc, esLoc) {
  if (!esLoc) return null;
  const english = Object.fromEntries(unitsOf(enLoc).map((unit) => [String(unit.name), unit.value]));
  if (esLoc.stringUnit && typeof esLoc.stringUnit.value === "string") {
    const value = toLatinAmericanSpanish(esLoc.stringUnit.value, english.null ?? "");
    if (value === esLoc.stringUnit.value) return null;
    return { stringUnit: { state: "translated", value } };
  }
  const plural = esLoc.variations?.plural;
  if (!plural) return null;
  let changed = false;
  const next = {};
  for (const [name, variant] of Object.entries(plural)) {
    const value = toLatinAmericanSpanish(variant.stringUnit.value, english[name] ?? "");
    if (value !== variant.stringUnit.value) changed = true;
    next[name] = { stringUnit: { state: "translated", value } };
  }
  return changed ? { variations: { plural: next } } : null;
}

function insertAfter(localizations, after, id, localization) {
  const next = {};
  let placed = false;
  for (const [key, value] of Object.entries(localizations)) {
    next[key] = value;
    if (key === after) {
      next[id] = localization;
      placed = true;
    }
  }
  if (!placed) next[id] = localization;
  return next;
}

/**
 * Adds en-GB / es-MX only where the text differs. Message-pool items stay
 * independent: a missing item falls back one by one, so identical lines are
 * left out.
 */
export function applyRegionalVariants(catalog) {
  const strings = catalog.strings ?? {};
  let enGB = 0;
  let esMX = 0;
  for (const entry of Object.values(strings)) {
    const localizations = entry.localizations ?? {};
    const british = mapLocalization(localizations.en, toBritishEnglish);
    const latin = spanishLocalization(localizations.en, localizations.es);
    let next = localizations;
    if (british) {
      next = insertAfter(next, "en", "en-GB", british);
      enGB += 1;
    }
    if (latin) {
      next = insertAfter(next, "es", "es-MX", latin);
      esMX += 1;
    }
    if (next !== localizations) entry.localizations = next;
  }
  return { enGB, esMX, total: Object.keys(strings).length };
}
