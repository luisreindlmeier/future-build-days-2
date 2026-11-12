"""Offline contract checks for the projects bridge and the team's server-side rules."""
import json
import os
from pathlib import Path
import runpy
import sys
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
COMPONENTS = Path(os.environ.get('KAIROS_COMPONENTS', '/home/legeant/future-build-days-2'))
os.environ['OPENAI_API_KEY'] = ''
sys.argv = ['kairos_server', '--agent-dir', str(COMPONENTS / 'prediction-agent'),
            '--projects-dir', str(COMPONENTS / 'projects-section')]
bridge = runpy.run_path(str(ROOT / 'tools/kairos_server.py'), run_name='bridge_test')


class Connections(unittest.TestCase):
    def setUp(self):
        self.data = {'assessment': json.loads((ROOT / 'samples/maya-kairos.json').read_text()),
                     'project': {'type': 'trip', 'name': 'Japan', 'description': 'Two weeks in Japan'}}

    def test_no_key_returns_honest_rules_without_inventing_estimates(self):
        result = bridge['project_plan'](self.data)
        self.assertEqual('rules', result['source'])
        self.assertIsNone(result['plan'])
        self.assertFalse(result['affordability']['loan_allowed'])

    def test_server_enforces_no_loan_and_saving_capacity_on_ai_output(self):
        reply = json.dumps({'verdict': 'good', 'summary': 'A trip', 'target_months': 12,
            'one_time_costs': [{'item': 'Travel', 'eur': 5000}], 'monthly_costs': [],
            'monthly_saving': 999999, 'loan': {'recommended': True, 'amount': 999999, 'years': 5}, 'risks': []})
        with patch.object(bridge['P'], '_cfg', return_value={'key': 'test'}), \
             patch.object(bridge['P'], '_call_model', return_value=reply) as call:
            result = bridge['project_plan'](self.data)
        self.assertEqual('ai', result['source'])
        self.assertEqual(0, result['plan']['loan']['amount'])
        self.assertLessEqual(result['plan']['monthlySaving'], result['affordability']['saving_capacity'])
        facts = json.loads(call.call_args.args[1])
        self.assertEqual('Customer', facts['client']['name'])
        self.assertEqual(self.data['assessment']['intake']['monthly_income'], facts['client']['income'])

    def test_bad_ai_response_falls_back(self):
        with patch.object(bridge['P'], '_cfg', return_value={'key': 'test'}), \
             patch.object(bridge['P'], '_call_model', return_value='not JSON'):
            self.assertEqual('rules', bridge['project_plan'](self.data)['source'])

    def test_invalid_project_rejected(self):
        self.data['project']['type'] = '__proto__'
        with self.assertRaises(ValueError):
            bridge['project_plan'](self.data)


if __name__ == '__main__':
    unittest.main(argv=['test_connections'], verbosity=2)
