// Reuses the team's exact planner prompt and affordability enforcement on the server.
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const input = JSON.parse(fs.readFileSync(0, 'utf8'));
const context = vm.createContext({ input, URLSearchParams, location: {search: ''}, console });
for (const file of ['config.js', 'engine.js', 'customer.js', 'ai.js']) {
  vm.runInContext(fs.readFileSync(path.join(process.argv[2], 'js', file), 'utf8'), context, {timeout: 3000});
}
const output = vm.runInContext(`(() => {
  const p = input.project;
  if (!Object.hasOwn(PROJECT_TYPES, p.type)) throw new Error('Unknown project type');
  globalThis.user = assessmentToUser(input.assessment);
  user.name = 'Customer';
  const facts = {
    client: {name: user.name, income: user.income, monthly_costs: user.costs,
      saving_capacity: user.capacity, savings: user.savings, vitals: user.vitals, level: user.level},
    customer_profile: user.profile,
    affordability: affordability(user, {...p, targetM: 0}),
    project: {type: p.type, name: p.name}, description: p.description,
    rules: CFG.caps, rates: CFG.rates, market: CFG.market,
    city_prices_eur_sqm: CFG.cities, today: 'Nov 2026'
  };
  if (input.reply !== undefined) {
    const verdict = parseVerdict(input.reply);
    if (!Array.isArray(verdict.one_time_costs) || !verdict.one_time_costs.length ||
        !['good','adjust','not_yet'].includes(verdict.verdict)) throw new Error('Invalid planner response');
    const plan = fixPlan(verdict, p);
    return {plan, targetM: p.targetM, affordability: affordability(user, p)};
  }
  return {system: AI_PLAN_SYSTEM, facts};
})()`, context, {timeout: 3000});
process.stdout.write(JSON.stringify(output));
