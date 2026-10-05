import { describe, expect, it } from "vitest";
import { applyRegionalVariants, regionalVariant, toBritishEnglish, toLatinAmericanSpanish } from "./regional-variants.mjs";

describe("regional variants", () => {
  it("changes British spelling and roster wording, and leaves the rest", () => {
    expect(toBritishEnglish("Use wallpaper colors")).toBe("Use wallpaper colours");
    expect(toBritishEnglish("Customize licenses")).toBe("Customise licences");
    expect(toBritishEnglish("Holiday calendar")).toBe("Bank holiday calendar");
    expect(toBritishEnglish("Hours & schedule")).toBe("Hours & rota");
    expect(toBritishEnglish("Free roster")).toBe("Free rota");
    expect(toBritishEnglish("Schedule")).toBe("Schedule");
    expect(toBritishEnglish("schedule the reminder")).toBe("schedule the reminder");
    expect(toBritishEnglish("scheduled overtime")).toBe("scheduled overtime");
    expect(toBritishEnglish("Keep {{name}}")).toBe("Keep {{name}}");
    expect(regionalVariant("en-GB", "overtime")).toBe("overtime");
  });

  it("uses Latin American wording only where the English noun is the roster", () => {
    expect(toLatinAmericanSpanish("cuenta atrás", "countdown")).toBe("cuenta regresiva");
    expect(toLatinAmericanSpanish("una notificación silenciosa cuenta atrás hasta la salida", "counts down")).toBe(
      "una notificación silenciosa hace la cuenta regresiva hasta la salida"
    );
    expect(toLatinAmericanSpanish("Festivos y días", "Holidays")).toBe("Feriados y días");
    expect(toLatinAmericanSpanish("Ajustes", "Settings")).toBe("Configuración");
    expect(toLatinAmericanSpanish("tus ajustes se quedarán aquí", "your settings will stay")).toBe(
      "tu configuración se quedará aquí"
    );
    expect(toLatinAmericanSpanish("Horario y turnos", "Hours & schedule")).toBe("Horas y rol de turnos");
    expect(toLatinAmericanSpanish("Horario libre", "Free roster")).toBe("Rol de turnos libre");
    expect(toLatinAmericanSpanish("Poner el horario", "Set the hours")).toBe("Poner el horario");
    expect(toLatinAmericanSpanish("Horario", "Hours")).toBe("Horario");
    expect(toLatinAmericanSpanish("fuera del horario laboral", "outside working hours")).toBe("fuera del horario laboral");
    expect(toLatinAmericanSpanish("jornada", "workday")).toBe("jornada");
  });

  it("stores a catalog variant only when the text differs", () => {
    const catalog = {
      strings: {
        same: { localizations: { en: { stringUnit: { state: "translated", value: "Hello" } }, es: { stringUnit: { state: "translated", value: "Hola" } } } },
        colour: { localizations: { en: { stringUnit: { state: "translated", value: "color" } }, es: { stringUnit: { state: "translated", value: "color" } } } },
      },
    };
    const counts = applyRegionalVariants(catalog);
    expect(counts).toMatchObject({ enGB: 1, esMX: 0 });
    expect(catalog.strings.same.localizations["en-GB"]).toBeUndefined();
    expect(catalog.strings.colour.localizations["en-GB"].stringUnit.value).toBe("colour");
  });
});
