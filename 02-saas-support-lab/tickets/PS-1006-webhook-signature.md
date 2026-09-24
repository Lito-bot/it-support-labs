# PS-1006 — "Webhook signature fails, but only sometimes"

> Reproduced in the lab: [`scenarios/ps-1006-signature-accents.sh`](../scenarios/ps-1006-signature-accents.sh) → [`evidence/ps-1006-signature-accents.txt`](../evidence/ps-1006-signature-accents.txt)
> **Escalated to engineering:** [ENG-2041](ENG-2041-signature-non-ascii.md)

| Field | Value |
|---|---|
| **Customer** | Sur Market |
| **Priority** | P2 — some shipment updates never reach their system |
| **Channel** | Email |
| **Outcome** | **Product bug** — escalated with root cause, reproduction and failing test; workaround given |

## Customer message

> "Our webhook endpoint rejects some of your webhooks because the signature doesn't match. Most work, a few don't, always the same way. We use the verification code from your docs."

## Investigation

"Some fail, most work" means something differs between those events. Worth finding what, before touching their code.

1. Created two test shipments for their account, one to **Rosario** and one to **Córdoba**. Their handler accepted the first and rejected the second **3 times** (all our retries):

   ```
   order_updated       evt_3966327e305a50ad  PCL08000128   ← Rosario
   signature_mismatch  evt_96bd37d78803ab2b  (x3)          ← Córdoba
   ```

2. Checked the pattern across all their events: **every** rejected event contains a non-ASCII character, and every event without one was accepted.

   ```
    has_non_ascii | events | signature_rejected
    f             |      4 |                  0
    t             |      1 |                  1
   ```

3. Their verification follows our docs: it HMACs the raw body. So either the body or the signed bytes are not what the docs say. Serializing the same payload the two ways our service could do it:

   ```
   body sent (UTF-8):   b'{"recipient_city": "C\xc3\xb3rdoba"}'
   what gets signed:    b'{"recipient_city": "C\\u00f3rdoba"}'
   ```

   Identical for plain ASCII, different as soon as there's an accent. We sign one serialization and send another. **This is our bug, not theirs.**

4. Wrote a test that reproduces it (`test_signature_verifies_for_non_ascii_payload`, marked `xfail` with the ENG ticket) so engineering can confirm the fix by turning it green.

## Reply to the customer

> Hi, thanks for the detailed report. You were right, and your verification code is fine: this is a bug on our side.
>
> It happens only when the webhook contains accented characters (like "Córdoba"). In those cases the signature we send doesn't match the body. I've reproduced it and passed it to our engineering team with everything they need to fix it.
>
> Until it's fixed, you don't lose anything: any shipment whose webhook was rejected is still correct in Parcelo, and you can fetch it with `GET /v1/shipments`. If you can, run a short reconciliation once a day for shipments updated recently. Please **don't** turn off signature verification to work around it. I'll update you as soon as the fix is out.

**Tags:** `webhooks` `hmac` `signature` `encoding` `utf-8` `escalation` `bug`
