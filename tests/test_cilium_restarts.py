import copy
import json
from pathlib import Path
import subprocess
import tempfile
import unittest


FILTER = Path(__file__).resolve().parents[1] / 'apps/components/cluster-autoscaler/files/cilium-restarts.jq'


class CiliumRestarts(unittest.TestCase):
    def setUp(self):
        self.nodes = {'items': [{'metadata': {'name': 'worker', 'labels': {'talos.dev/nodepool': 'spot'}}, 'status': {'addresses': [{'type': 'InternalIP', 'address': '10.0.0.2'}], 'conditions': [{'type': 'Ready', 'status': 'True', 'lastTransitionTime': '2026-01-01T00:00:00Z'}]}}]}
        self.cilium = {'items': [{'metadata': {'name': 'worker'}, 'spec': {'addresses': [{'type': 'InternalIP', 'ip': '10.0.0.1'}]}}]}
        self.pods = {'items': [{'metadata': {'name': 'cilium-worker', 'uid': 'pod-uid', 'resourceVersion': '42'}, 'spec': {'nodeName': 'worker'}, 'status': {'phase': 'Running', 'containerStatuses': [{'name': 'cilium-agent', 'state': {'running': {'startedAt': '2026-01-01T00:00:00Z'}}}]}}]}
        self.now = 1767226200

    def select(self):
        with tempfile.TemporaryDirectory() as tmp:
            for name, value in [('nodes', self.nodes), ('pods', self.pods)]:
                Path(tmp, name).write_text(json.dumps(value))
            result = subprocess.check_output(['jq', '-c', '--slurpfile', 'nodes', tmp + '/nodes', '--slurpfile', 'pods', tmp + '/pods', '--argjson', 'now', str(self.now), '-f', str(FILTER)], input=json.dumps(self.cilium).encode()).strip()
            return json.loads(result) if result else None

    def test_stale_ready_worker_preserves_delete_preconditions(self):
        self.assertEqual(self.select(), {'node': 'worker', 'pod': 'cilium-worker', 'uid': 'pod-uid', 'version': '42', 'ip': '10.0.0.2', 'old': '10.0.0.1'})

    def test_matching_address(self):
        self.cilium['items'][0]['spec']['addresses'][0]['ip'] = '10.0.0.2'
        self.assertIsNone(self.select())

    def test_unready_worker(self):
        self.nodes['items'][0]['status']['conditions'][0]['status'] = 'False'
        self.assertIsNone(self.select())

    def test_control_plane(self):
        self.nodes['items'][0]['metadata']['labels']['talos.dev/nodepool'] = 'controlplane'
        self.assertIsNone(self.select())

    def test_startup_grace(self):
        self.now = 1767225660
        self.assertIsNone(self.select())

    def test_terminating_agent(self):
        self.pods['items'][0]['metadata']['deletionTimestamp'] = '2026-01-01T00:01:00Z'
        self.assertIsNone(self.select())

    def test_missing_address(self):
        self.cilium['items'][0]['spec']['addresses'] = []
        self.assertIsNone(self.select())

    def test_restarts_at_most_one_agent(self):
        for collection in [self.nodes, self.cilium, self.pods]:
            second = copy.deepcopy(collection['items'][0])
            second['metadata']['name'] += '-second'
            if 'spec' in second and 'nodeName' in second['spec']:
                second['spec']['nodeName'] = 'worker-second'
            collection['items'].append(second)
        self.assertEqual(self.select()['node'], 'worker')


if __name__ == '__main__':
    unittest.main()
