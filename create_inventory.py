
import json
import sys


_AGENT_YML = """
version: 1

control-service:
  hostname: %s
  port: 4524

dataset:
  backend: gce
"""


def main(input_data):
    instances = [
        {
            u'ip': i[u'networkInterfaces'][0][u'accessConfigs'][0][u'natIP'],
            u'name': i[u'name']
        }
        for i in input_data
    ]

    with open('./ansible_inventory', 'w') as inventory_output:
        inventory_output.write('[flocker_control_service]\n')
        inventory_output.write(instances[0][u'ip'] + '\n')
        inventory_output.write('\n')
        inventory_output.write('[flocker_agents]\n')
        for instance in instances:
            inventory_output.write(instance[u'ip'] + '\n')
        inventory_output.write('\n')
        inventory_output.write('[nodes:children]\n')
        inventory_output.write('flocker_control_service\n')
        inventory_output.write('flocker_agents\n')

    with open('./agent.yml', 'w') as agent_yml:
        agent_yml.write(_AGENT_YML % instances[0][u'ip'])


if __name__ == '__main__':
    if sys.stdin.isatty():
        raise SystemExit("Must pipe input into this script.")
    stdin_json = json.load(sys.stdin)
    main(stdin_json)
