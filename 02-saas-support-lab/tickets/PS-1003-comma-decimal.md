# PS-1003 — "The API rejects our weights"

> Reproduced in the lab: [`scenarios/ps-1003-comma-decimal.sh`](../scenarios/ps-1003-comma-decimal.sh) → [`evidence/ps-1003-comma-decimal.txt`](../evidence/ps-1003-comma-decimal.txt)

| Field | Value |
|---|---|
| **Customer** | Pampa Outdoor |
| **Priority** | P3 — some orders fail, workaround possible |
| **Channel** | Email, in Spanish |
| **Outcome** | Customer-side data format + product improvement filed |

## Customer message

> "Nos rechaza los envíos con error 422 'unable to parse string as a number'. El peso está bien, 2,5 kg. ¿Qué número quiere?"

## Investigation

Their request body:

```json
{"recipient_city": "Tandil", "weight_kg": "2,5"}
```

The response already names the field and the input:

```json
{"detail": [{"type": "float_parsing", "loc": ["body", "weight_kg"],
             "msg": "Input should be a valid number, unable to parse string as a number", "input": "2,5"}]}
```

Two things are wrong, both from a spreadsheet export using Argentine number formatting:
- **Comma as the decimal separator.** JSON numbers always use a dot.
- **The number sent as a string** (`"2,5"` in quotes). It should be a plain JSON number.

With `"weight_kg": 2.5` → 201.

## Reply to the customer (in their language)

> ¡Hola! El problema está en el formato del peso. La API espera un número con punto decimal y sin comillas, así: `"weight_kg": 2.5`. Ustedes están mandando `"2,5"`, con coma y entre comillas, que es como lo exporta la planilla con la configuración regional de Argentina.
>
> Si en la integración convierten el valor antes de enviarlo (reemplazar la coma por punto y mandarlo como número), va a funcionar. Probé el mismo envío con `2.5` y se creó bien.

## Follow-up (internal)

- Feature request filed: when a number field fails to parse and the input matches `^\d+,\d+$`, add a hint like *"use a dot as decimal separator: 2.5"*. We have many LATAM customers, and the generic parser message doesn't help a non-developer.

**Tags:** `api` `validation` `422` `localization` `spanish`
