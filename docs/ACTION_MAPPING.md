# One plan, one commit flow

Show the agent's `actions.output.actions` from `/api/users/{id}/prediction`, or
`action_agent.actions` from `/api/users/{id}/kairos`. Join each item's `action_id`
to `GET /api/users/{id}/actions/mapping`.

Each mapping contains `backendActionId`, `canCommit`, the current backend `action`
(including title, monthly and one-off amounts), and a reason when unavailable.
Unknown IDs must be treated as unavailable. Fetch mappings again after a month advances
or customer data changes.

| Agent ID | Backend ID |
|---|---|
| `limit_eating_out` | `act-limit-eating_out` |
| `limit_shopping` | `act-limit-shopping` |
| `limit_travel` | `act-limit-travel` |
| `limit_subscriptions` | `act-limit-subscriptions` |
| `limit_other` | `act-limit-other` |
| `start_buffer` | `act-buffer` |
| `save_more_tomorrow` | `act-savings-plan` |
| `family_diversification_plan` | `act-diversify` |
| `income_protection_check` | `act-protect` |

`canCommit` is true only when that backend recommendation currently exists for that
person. A mapping is a semantic connection, not agreement between the two engines'
amounts. Display the returned backend action title and amounts at the commit button;
those are the terms actually committed. In particular, a buffer can be a one-off cash
transfer rather than a monthly standing order. The agent's simulated impact is not a
prediction of the backend's differently sized action.

Both canonical IDs and supported agent aliases work:

```js
const base = 'http://localhost:8080/api/users/maya';
const mappings = await fetch(`${base}/actions/mapping`).then(r => r.json());
const id = 'limit_eating_out'; // from the displayed agent plan
const mapping = mappings[id];
if (mapping?.canCommit) {
  // Show mapping.action.title and amounts before the user presses Commit.
  // On that click:
  const response = await fetch(`${base}/actions/${encodeURIComponent(id)}/commit`, {
    method: 'POST'
  });
  if (!response.ok) throw new Error('Action changed; refresh the plan.');
  const progress = await response.json();
}
```

`POST /api/users/{id}/actions/{actionId}/drop` accepts the same aliases, including
when the original recommendation is no longer available. Stored history always uses
canonical backend IDs. Repeating an unchanged commitment does not duplicate it.
Commitment alone does not verify the action: advance the demo month, then read progress,
tree and prediction again to see the verified effects.

These agent actions have **no equivalent tree action** and return `canCommit: false`:
`cancel_unused_subscriptions`, `pause_purchase`, `close_spending_gap`,
`write_crash_rules`, `write_will`. Keep them as advice without a tree commit button.
Cancelling a specific subscription is not equivalent to setting a category budget;
writing crash rules is not equivalent to completing a learning module. Unsupported or
no-longer-recommended IDs are rejected by commit with HTTP 404.

This checkout supplies the backend contract. The projects section is a life-project
planner; it does not currently render the action agent's recommendation list. A tree
frontend can consume this contract without showing a second recommendation list.
