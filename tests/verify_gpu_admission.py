import argparse
import copy
import json
import subprocess


GPU_KEYS = {'talos.dev/gpu', 'burst.talos.dev/gpu-training'}


def pod(namespace, claim=None, tolerations=None):
    result = {
        'apiVersion': 'v1',
        'kind': 'Pod',
        'metadata': {'generateName': 'gpu-admission-check-', 'namespace': namespace},
        'spec': {
            'restartPolicy': 'Never',
            'securityContext': {'runAsNonRoot': True, 'seccompProfile': {'type': 'RuntimeDefault'}},
            'containers': [{
                'name': 'check', 'image': 'registry.k8s.io/pause:3.10',
                'securityContext': {'allowPrivilegeEscalation': False, 'capabilities': {'drop': ['ALL']}},
            }],
        },
    }
    if claim:
        result['spec']['resourceClaims'] = [{'name': 'gpu', 'resourceClaimName': claim}]
        result['spec']['containers'][0]['resources'] = {'claims': [{'name': 'gpu'}]}
    if tolerations is not None:
        result['spec']['tolerations'] = tolerations
    return result


def verify(kubeconfig):
    def admit(value):
        return json.loads(subprocess.check_output([
            'kubectl', '--kubeconfig', kubeconfig, 'create', '--dry-run=server', '-f', '-', '-o', 'json',
        ], input=json.dumps(value).encode()))

    def gpu_tolerations(value):
        return [t for t in value['spec'].get('tolerations', []) if t.get('key') in GPU_KEYS]

    for namespace, claim in [('ml', 'ml-gpu'), ('llm', 'llm-gpu')]:
        admitted = admit(pod(namespace, claim))
        tolerations = gpu_tolerations(admitted)
        assert {t['key'] for t in tolerations} == GPU_KEYS, admitted
        assert all(t['operator'] == 'Equal' and t['value'] == 'true' and t['effect'] == 'NoSchedule' for t in tolerations)
        assert not admitted['spec'].get('nodeSelector'), admitted
        repeated = admit(pod(namespace, claim, admitted['spec']['tolerations']))
        assert gpu_tolerations(repeated) == tolerations, repeated
        print(namespace, claim, 'injected without node selector; repeated admission is idempotent')

    for namespace, claim in [('ml', None), ('ml', 'other-gpu'), ('llm', 'ml-gpu'), ('default', 'llm-gpu')]:
        admitted = admit(pod(namespace, claim))
        assert not gpu_tolerations(admitted), admitted
        print(namespace, claim, 'unmodified')

    existing = [
        {'key': 'custom', 'operator': 'Exists', 'effect': 'NoExecute'},
        {'key': 'talos.dev/gpu', 'operator': 'Exists', 'effect': 'NoSchedule'},
    ]
    admitted = admit(pod('ml', 'ml-gpu', copy.deepcopy(existing)))
    assert all(t in admitted['spec']['tolerations'] for t in existing), admitted
    assert len(gpu_tolerations(admitted)) == 2, admitted

    wildcard = [{'operator': 'Exists', 'effect': 'NoSchedule'}]
    admitted = admit(pod('ml', 'ml-gpu', wildcard))
    assert not gpu_tolerations(admitted), admitted
    assert wildcard[0] in admitted['spec']['tolerations'], admitted
    print('existing custom and wildcard tolerations preserved without duplicates')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--kubeconfig', required=True)
    verify(parser.parse_args().kubeconfig)
