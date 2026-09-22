// ══════════════════════════════════════════════════════════════════════════
// INVISIBLE, SCORE-BASED BOT PROTECTION for the payment-submission action.
//
// SHAPE OF THE INTEGRATION
// ------------------------
// This scores ONE ACTION — pressing Pay — rather than gating the /checkout
// page behind a visible puzzle. That is the documented way to use a
// score-based provider and it is the right trade here: a customer who has
// already signed in, already seen the price and already decided to buy is the
// worst possible person to interrupt with a grid of traffic lights. The token
// is minted in the browser when Pay is pressed and assessed here, server-side,
// before any order is opened.
//
// PROVIDER
// --------
// Written against reCAPTCHA Enterprise's assessment response, because the
// task's whole premise is a SCORE with graduated handling, and Enterprise is
// the option that returns a 0.0–1.0 score plus the action name it was minted
// for. The provider is reached through one `fetch` in create-order; swapping
// it means changing that call and `parseEnterpriseAssessment` below, not this
// file's decision logic.
//
// ⚠ NOT YET PROVISIONED. There is no reCAPTCHA Enterprise project on this
// account and no key to configure — see RECAPTCHA_* in the deployment notes.
// Until the owner creates one, `configured: false` is the live state and this
// module returns `allow` for everyone. That is deliberate and is the only
// safe default: an unconfigured anti-fraud control that silently refused
// payments would be an outage that looks like a fraud policy.
//
// WHY IT CANNOT DECLINE EITHER
// ----------------------------
// Same reasoning as avs.ts, and the same type-level guarantee: there is no
// `block` verdict in `BotVerdict`. A score is a probability, not a finding.
// Google's own guidance is that a low score should adjust friction, not
// refuse service, and reCAPTCHA scores are known to sit low for real people
// on VPNs, on privacy-hardened browsers, on Tor, and on older Android
// WebViews — all of which describe a plausible customer for a diagnostics app
// sold to motorcycle mechanics.
//
// So the worst verdict available is `throttle`, which spends the requester's
// rate-limit budget faster (the caller adds +1 to the burst count) and writes
// an audit row. A single low-scoring human still checks out on their first
// attempt. Only a low-scoring requester making REPEATED attempts — which is
// the card-testing pattern itself, and which the rate limiter would catch on
// its own eventually — is slowed down, and even then they are slowed, not
// refused.
// ══════════════════════════════════════════════════════════════════════════

/** reCAPTCHA Enterprise scores: 0.0 = almost certainly a bot, 1.0 = human. */
export const SCORE_ALLOW = 0.5;
export const SCORE_FLAG = 0.3;

/** The action name the browser must mint the token for. */
export const CHECKOUT_ACTION = "intl_checkout_pay";

export type BotVerdict =
  /** Proceed normally. */
  | "allow"
  /** Proceed normally, but write an audit row. */
  | "flag"
  /** Proceed, and spend rate-limit budget faster. Still not a refusal. */
  | "throttle";

export type BotAssessment = {
  verdict: BotVerdict;
  /** null when the provider is not configured or the token was unusable. */
  score: number | null;
  note: string;
};

export type EnterpriseAssessment = {
  /** Did the token itself parse and belong to this site key? */
  valid: boolean;
  /** The action the token was minted for, as reported by the provider. */
  action: string | null;
  score: number | null;
};

/**
 * Narrow the provider's JSON into the three fields the decision needs.
 * Tolerant by design: a response shape we do not recognise becomes
 * `valid: false`, which the decision below treats as "no signal", not as
 * "guilty".
 */
export function parseEnterpriseAssessment(body: unknown): EnterpriseAssessment {
  const b = (body ?? {}) as Record<string, unknown>;
  const tokenProps = (b.tokenProperties ?? {}) as Record<string, unknown>;
  const risk = (b.riskAnalysis ?? {}) as Record<string, unknown>;

  const score = typeof risk.score === "number" ? risk.score : null;
  return {
    valid: tokenProps.valid === true,
    action: typeof tokenProps.action === "string" ? tokenProps.action : null,
    score,
  };
}

/**
 * Graduated handling. Note every branch returns a verdict that lets the
 * payment proceed.
 *
 * @param configured false when no provider credentials are set. Fails OPEN.
 */
export function assessBotScore(input: {
  configured: boolean;
  assessment?: EnterpriseAssessment | null;
  expectedAction?: string;
}): BotAssessment {
  if (!input.configured) {
    return {
      verdict: "allow",
      score: null,
      note: "Bot protection not configured — no signal, proceeding.",
    };
  }

  const a = input.assessment;
  if (!a || !a.valid || a.score === null) {
    // A missing or unparseable token is suspicious but not probative: ad
    // blockers, strict tracking protection and corporate proxies all break
    // the provider's script for entirely ordinary customers.
    return {
      verdict: "flag",
      score: a?.score ?? null,
      note: "Bot-protection token missing or invalid — recorded, proceeding.",
    };
  }

  const expected = input.expectedAction ?? CHECKOUT_ACTION;
  if (a.action !== expected) {
    // A token minted for a different action and replayed at checkout is the
    // classic token-reuse attempt. Still not a decline — it is also what a
    // stale page produces after a deploy changes the action name.
    return {
      verdict: "throttle",
      score: a.score,
      note:
        `Token action '${a.action}' != expected '${expected}' — throttled, proceeding.`,
    };
  }

  if (a.score >= SCORE_ALLOW) {
    return { verdict: "allow", score: a.score, note: `Score ${a.score}.` };
  }
  if (a.score >= SCORE_FLAG) {
    return {
      verdict: "flag",
      score: a.score,
      note: `Score ${a.score} below ${SCORE_ALLOW} — recorded, proceeding.`,
    };
  }
  return {
    verdict: "throttle",
    score: a.score,
    note: `Score ${a.score} below ${SCORE_FLAG} — throttled, proceeding.`,
  };
}
