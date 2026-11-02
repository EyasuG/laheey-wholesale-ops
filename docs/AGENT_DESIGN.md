# Agentforce design: Laheey Wholesale Assistant

An internal (employee) agent for sales reps and the operations team. It answers two kinds of questions with real data, and politely declines everything else.

## Org prerequisites

- An org with Agentforce, Agentforce Builder and Prompt Builder. Easiest: the Developer Edition org provisioned by the Trailhead superbadge **Apex for Agentforce**, or an Agentforce Labs org.
- This project deployed (SETUP step 6) and a Developer Edition slice loaded (SETUP step 8).
- For warehouse fallbacks on old orders: the Named Credential from SETUP step 7. Without it, the action says it can't reach the order system, which is the designed behavior.

Salesforce renamed agent *topics* to **subagents** in April 2026; older Trailhead content uses "topics".

## The agent

| Setting | Value |
|---|---|
| Type | Employee agent (internal staff) |
| Name | Laheey Wholesale Assistant |
| Role | Helps Laheey sales reps and operations staff check wholesale order status and account health. Uses only data returned by its actions. |
| Company | Laheey Coffee Roasters roasts Ethiopian and single-origin coffee and sells wholesale to cafes, grocers, offices, restaurants, hotels and universities. |

## Subagents and actions

### 1. Order Status

| | |
|---|---|
| Classification | Questions about where an order is, whether it shipped, when it shipped, what it cost or whether it's paid. |
| Action | **Get Wholesale Order Status** (Apex `OrderStatusAction`, input: Order Number) |
| Instructions | Always get the order number before calling the action; if the user hasn't given one, ask for it. Order numbers look like LWO followed by 8 digits. Answer using the action's Summary. Never guess a status, date or amount. If the action says the order system is unreachable, say so and suggest trying again later. |

**Deterministic rule (Agent Script).** In Script view, add a condition so the action runs only when the captured order number matches the `LWO-` pattern, and otherwise transitions back to asking for the number. This is the "deterministic behavior" the Agentforce Specialist exam tests: the LLM decides *what the user wants*; the script guarantees *the action never runs on bad input*. Use the Agent Script docs and the `trailheadapps/agent-script-recipes` examples for current syntax.

### 2. Account Insights

| | |
|---|---|
| Classification | Questions about how a wholesale account is doing, whether it's at risk, its revenue, last order, open cases, or what to do next with it. |
| Action | **Get Wholesale Account Insights** (Apex `AccountInsightAction`, input: Account Id) |
| Instructions | Identify the account from the record the user is viewing; if none, ask which account and use a standard record lookup to find its Id. Answer with the action's Summary, leading with the health status. Don't share contact details or anything not returned by the action. |

### Why these actions are Apex

- They reuse `AccountHealthService`, so the agent's answer always matches the Account Health card and the batch.
- They're bulk-safe and permission-aware (`WITH USER_MODE`): the agent can't show a rep an account they can't see.
- `OrderStatusAction` checks Salesforce first and calls the warehouse only for orders older than the sync window (`callout=true`).
- The `label` and `description` on `@InvocableMethod` and each `@InvocableVariable` are what the reasoning engine reads. They're written as instructions, not as code comments.

## Prompt template: Reorder Nudge

Prompt Builder → New → **Sales Email** template (or **Flex** with an Account input).

| Setting | Value |
|---|---|
| Name | Reorder Nudge |
| Grounding | Account: Name, Tier, Segment, Last Order Date, Revenue (12 Months), Health Status; Primary contact's first name |
| Instruction (outline) | Write a short, warm email from the account's sales rep to the primary contact. Mention how long it's been since the last order only if it's over 30 days. Suggest one Ethiopian single origin they haven't tried. No discounts unless the tier is Platinum. Under 120 words. Plain language. |

Test it on a Healthy account and an At Risk account; compare the tone. Expose it to reps as an action on the Account page, or to the agent as a third action.

## Guardrails

- Scope: orders and wholesale accounts only. Off-topic requests (recipes, HR questions, competitor pricing) get a one-line decline and a reminder of what it can do.
- No invented numbers: every figure comes from an action result.
- Data minimization: actions return summaries, not raw records; no emails or phone numbers.
- Einstein Trust Layer: confirm data masking and zero retention are on in Setup; check the audit trail after testing.

## Testing Center suite

| # | Utterance | Expected subagent | Expected action | Expected outcome |
|---|---|---|---|---|
| 1 | Where is order LWO-00000091? | Order Status | Get Wholesale Order Status | States status and ship date |
| 2 | Has my order shipped? | Order Status | none (asks first) | Asks for the order number |
| 3 | Order LWO-99999999 status | Order Status | Get Wholesale Order Status | Says it can't find that order |
| 4 | Is order 12345 paid? | Order Status | none | Asks for a valid LWO- number (script rule) |
| 5 | How is this account doing? (on an account) | Account Insights | Get Wholesale Account Insights | Leads with health status and score |
| 6 | Which of my accounts should I call this week? | Account Insights | Get Wholesale Account Insights | Explains At Risk reasons (or asks which account) |
| 7 | What's the revenue for Blue Door Cafe? | Account Insights | lookup + insights | Gives 12-month revenue from the action |
| 8 | Write me a lasagna recipe | none | none | Declines, restates scope |
| 9 | Give me the owner's phone number | Account Insights | none | Declines to share contact details |

Pick real order numbers from your org for rows 1 and 3. Re-run the suite after every change to instructions or script.
